defmodule Boom.ObservationLog do
  use GenServer
  require Logger

  defmodule State do
    @enforce_keys [:ets]
    defstruct(
      next_id: 1,
      ets: nil
    )
  end

  import Boom.Guards
  alias Boom.Observation

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
      %Observation{type: Observation.Invalidate, active: true} -> false
      %Observation{} -> true
    end)
    |> Enum.filter(& &1.active)
  end

  def list_all(ets \\ @ets) do
    :ets.tab2list(ets)
    |> Enum.flat_map(&elem(&1, 1))
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

  def add(observations, pid \\ __MODULE__) when is_list(observations) do
    observations
    |> Enum.map(&add_one(&1, pid))
    |> Enum.uniq()
    |> Enum.map(fn target ->
      PubSub.publish(:observation_log, {:observation_added, target})
      Boom.ObjectSupervisor.ensure_started(target)
    end)
  end

  defp add_one(%Observation{} = observation, pid) do
    {:ok, %Observation{target: target} = observation} = GenServer.call(pid, {:add, observation})

    Boom.output([
      IO.ANSI.light_green(),
      to_string(observation),
      IO.ANSI.reset()
    ])

    target
  end

  def enable(id, pid \\ __MODULE__) when is_integer(id) do
    case list_all() |> Enum.find(&(&1.id == id)) do
      nil ->
        {:error, :not_found}

      %Observation{active: true} ->
        {:error, :already_enabled}

      %Observation{active: false, target: target} = obs ->
        :ok = GenServer.call(pid, {:enable, obs})
        PubSub.publish(:observation_log, {:observation_added, target})
        {:ok, obs}
    end
  end

  def disable(id, pid \\ __MODULE__) when is_integer(id) do
    case list_all() |> Enum.find(&(&1.id == id)) do
      nil ->
        {:error, :not_found}

      %Observation{active: false} ->
        {:error, :already_disabled}

      %Observation{active: true, target: target} = obs ->
        :ok = GenServer.call(pid, {:disable, obs})
        PubSub.publish(:observation_log, {:observation_disabled, target})
        {:ok, obs}
    end
  end

  def rollback(pid \\ __MODULE__) do
    with [_ | _] = entries <- list_all() |> Enum.filter(& &1.active) do
      %Observation{active: true, target: target} = obs = Enum.max_by(entries, & &1.id)
      :ok = GenServer.call(pid, {:disable, obs})
      PubSub.publish(:observation_log, {:observation_disabled, target})
      {:ok, obs}
    else
      [] -> {:error, :fully_rolled_back}
    end
  end

  def reset(pid \\ __MODULE__), do: GenServer.call(pid, :reset)

  @impl true
  def init(ets) when is_atom(ets) do
    :ets.new(ets, [:set, :protected, :named_table])
    Logger.info(@log_prefix <> "Started using table #{inspect(ets)}.")
    {:ok, %State{ets: ets}}
  end

  @impl true
  def handle_call(
        {:add, %Observation{target: target} = observation},
        _from,
        %State{next_id: next_id, ets: ets} = state
      ) do
    observation = %Observation{observation | id: next_id}
    entries = [observation | entries(target, ets)]

    :ets.insert(ets, [{target, entries}])
    {:reply, {:ok, observation}, %State{state | next_id: next_id + 1}}
  end

  @impl true
  def handle_call(
        {:disable, %Observation{id: id, target: target}},
        _from,
        %State{ets: ets} = state
      ) do
    entries(target, ets)
    |> Enum.map(fn
      %Observation{id: ^id} = obs -> %Observation{obs | active: false}
      %Observation{} = obs -> obs
    end)
    |> then(fn entries ->
      :ets.insert(ets, [{target, entries}])
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(
        {:enable, %Observation{id: id, target: target}},
        _from,
        %State{ets: ets} = state
      ) do
    entries(target, ets)
    |> Enum.map(fn
      %Observation{id: ^id} = obs -> %Observation{obs | active: true}
      %Observation{} = obs -> obs
    end)
    |> then(fn entries ->
      :ets.insert(ets, [{target, entries}])
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:reset, _from, %State{ets: ets}) do
    :ets.delete_all_objects(ets)
    {:reply, :ok, %State{ets: ets}}
  end
end
