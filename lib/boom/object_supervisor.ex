defmodule Boom.ObjectSupervisor do
  use DynamicSupervisor

  alias Boom.ObjectRegistry

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def ensure_started(obj_id) do
    case ObjectRegistry.whereis(obj_id) do
      nil -> start_object(obj_id)
      pid when is_pid(pid) -> {:ok, pid}
    end
  end

  defp start_object(obj_id) do
    case DynamicSupervisor.start_child(__MODULE__, {ObjectServer, obj_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_registered, pid}} -> {:ok, pid}
      {:error, _} = err -> err
    end
    |> then(fn
      {:ok, pid} -> {:ok, pid}
      {:error, _} = err -> err
    end)
  end
end
