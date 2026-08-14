defmodule Boom.ObjectRegistry do
  @special_names [:ownship]
  defguard is_object_name(name) when is_binary(name) or name in @special_names

  @geom_errors [:pending, :unknown, :disjoint]
  defguard is_geom_error(err) when err in @geom_errors
  defguard is_geometry(geom) when is_struct(geom) or is_geom_error(geom)

  def child_spec(opts) do
    Registry.child_spec(opts ++ [name: __MODULE__, keys: :unique])
  end

  def register(name) when is_object_name(name) do
    Registry.register(__MODULE__, canonical(name), {0, :pending})
  end

  def update(name, version, geometry)
      when is_object_name(name) and is_integer(version) and is_geometry(geometry) do
    Registry.update_value(__MODULE__, name, fn _ -> {version, geometry} end)
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

  def geometry(name) when is_object_name(name) do
    {_, _, geometry} = lookup(name)
    geometry
  end

  def all_geometries do
    Registry.select(__MODULE__, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.map(fn {name, {_version, geometry}} -> {name, geometry} end)
  end

  def count, do: Registry.count(__MODULE__)

  defp lookup(name) when is_object_name(name) do
    case Registry.lookup(__MODULE__, canonical(name)) do
      [{pid, {version, geometry}}] -> {pid, version, geometry}
      [] -> {nil, 0, :unknown}
    end
  end

  defp canonical(name) when is_binary(name), do: String.downcase(name)
  defp canonical(name) when name in @special_names, do: name
end
