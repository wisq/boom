defmodule Boom.ObjectSupervisor do
  use DynamicSupervisor

  alias Boom.Object
  alias Boom.ObjectRegistry

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def ensure_started(name) do
    case ObjectRegistry.whereis(name) do
      nil -> start_object(name)
      pid when is_pid(pid) -> {:ok, pid}
    end
  end

  defp start_object(name) do
    case DynamicSupervisor.start_child(__MODULE__, {Object, name}) do
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
