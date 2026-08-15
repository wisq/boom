defmodule Boom.ObjectRegistry do
  import Boom.Guards

  def child_spec(opts) do
    Registry.child_spec(opts ++ [name: __MODULE__, keys: :unique])
  end

  def register(name) when is_object_name(name) do
    Registry.register(__MODULE__, canonical(name), {0, :pending})
  end

  def update(name, version, solution)
      when is_object_name(name) and is_integer(version) and is_solution(solution) do
    Registry.update_value(__MODULE__, name, fn _ -> {version, solution} end)
    PubSub.publish(:object_registry, {:object_updated, name})
  end

  def whereis(name) when is_object_name(name) do
    {pid, _, _} = lookup(name)
    pid
  end

  def version(name) when is_object_name(name) do
    {_, version, _} = lookup(name)
    version
  end

  def solution(name) when is_object_name(name) do
    {_, _, solution} = lookup(name)
    solution
  end

  def all_solutions do
    Registry.select(__MODULE__, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.map(fn {name, {_version, solution}} -> {name, solution} end)
  end

  def count, do: Registry.count(__MODULE__)

  defp lookup(name) when is_object_name(name) do
    case Registry.lookup(__MODULE__, canonical(name)) do
      [{pid, {version, solution}}] -> {pid, version, solution}
      [] -> {nil, 0, :unknown}
    end
  end

  @special_names Boom.Defines.special_object_names()
  defp canonical(name) when is_binary(name), do: String.downcase(name)
  defp canonical(name) when name in @special_names, do: name
end
