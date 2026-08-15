defmodule Boom.CommandLog do
  use GenServer
  require Logger

  defmodule State do
    @enforce_keys [:ets]
    defstruct(
      next_id: 1,
      ets: nil
    )
  end

  import Boom.ObjectRegistry, only: [is_object_name: 1]
  alias Boom.Command

  @ets __MODULE__.ETS
  @log_prefix "[#{inspect(__MODULE__)}] "

  def start_link(opts) do
    {ets, opts} = Keyword.pop(opts, :ets, @ets)
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, ets, opts)
  end

  def entries(name, ets \\ @ets) when is_object_name(name) do
    case :ets.lookup(ets, name) do
      [{^name, ents}] when is_list(ents) -> ents
      [] -> []
    end
  end

  def active_entries(name, ets \\ @ets) when is_object_name(name) do
    entries(name, ets)
    |> Enum.take_while(fn
      %Command{type: Command.Invalidate, active: true} -> false
      %Command{} -> true
    end)
    |> Enum.filter(& &1.active)
  end

  def count_all(ets \\ @ets) do
    :ets.foldl(
      fn {_, entries}, acc ->
        acc + Enum.count(entries)
      end,
      0,
      ets
    )
  end

  def add(commands, pid \\ __MODULE__) when is_list(commands) do
    commands
    |> Enum.map(&add_one(&1, pid))
    |> Enum.uniq()
    |> Enum.map(fn target ->
      PubSub.publish(:command_log, {:command_added, target})
      Boom.ObjectSupervisor.ensure_started(target)
    end)
  end

  defp add_one(%Command{} = command, pid) do
    {:ok, %Command{target: target} = command} = GenServer.call(pid, {:add, command})

    Boom.output([
      IO.ANSI.light_green(),
      to_string(command),
      IO.ANSI.normal()
    ])

    target
  end

  @impl true
  def init(ets) when is_atom(ets) do
    :ets.new(ets, [:set, :protected, :named_table])
    Logger.info(@log_prefix <> "Started using table #{inspect(ets)}.")
    {:ok, %State{ets: ets}}
  end

  @impl true
  def handle_call(
        {:add, %Command{target: target} = command},
        _from,
        %State{next_id: next_id, ets: ets} = state
      ) do
    command = %Command{command | id: next_id}
    entries = [command | entries(target, ets)]

    :ets.insert(ets, [{target, entries}])
    {:reply, {:ok, command}, %State{state | next_id: next_id + 1}}
  end
end
