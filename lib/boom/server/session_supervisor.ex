defmodule Boom.Server.SessionSupervisor do
  use DynamicSupervisor

  alias Boom.Server.Session

  @ets __MODULE__.ETS

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    :ets.new(@ets, [:set, :public, :named_table])
    :ets.insert(@ets, id: 0)
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_session(port) do
    id = :ets.update_counter(@ets, :id, 1)
    DynamicSupervisor.start_child(__MODULE__, {Session, id: id, port: port})
  end
end
