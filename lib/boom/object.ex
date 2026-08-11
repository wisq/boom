defmodule Boom.Object do
  use GenServer
  alias Boom.ObjectRegistry

  def child_spec(opts) do
    super(opts)
    |> Map.put(:restart, :temporary)
  end

  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    GenServer.start_link(__MODULE__, name, opts)
  end

  defmodule State do
    @enforce_keys [:name]
    defstruct(@enforce_keys)
  end

  @impl true
  def init(name) do
    with {:ok, _} <- ObjectRegistry.register(name) do
      {:ok, %State{name: name}}
    end
  end
end
