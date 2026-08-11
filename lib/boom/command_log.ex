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

  @ets __MODULE__.ETS
  @log_prefix "[#{inspect(__MODULE__)}] "

  def start_link(opts) do
    Keyword.put_new(opts, :name, __MODULE__)
    {ets, opts} = Keyword.pop(opts, :ets, @ets)
    GenServer.start_link(__MODULE__, ets, opts)
  end

  def entries(name, ets \\ @ets) when is_object_name(name) do
    case :ets.lookup(ets, name) do
      [{^name, ents}] when is_list(ents) -> ents
      [] -> []
    end
  end

  @impl true
  def init(ets) when is_atom(ets) do
    :ets.new(ets, [:set, :protected, :named_table])
    Logger.info(@log_prefix <> "Started using table #{inspect(ets)}.")
    {:ok, %State{ets: ets}}
  end
end
