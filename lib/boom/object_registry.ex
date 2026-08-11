defmodule Boom.ObjectRegistry do
  @special_names [:ownship]
  defguard is_object_name(name) when is_binary(name) or name in @special_names

  def child_spec(opts) do
    Registry.child_spec(opts ++ [name: __MODULE__, keys: :unique])
  end

  def register(name) when is_object_name(name) do
    Registry.register(__MODULE__, canonical(name), :pending)
  end

  def whereis(name) when is_object_name(name) do
    case lookup(name) do
      {pid, _value} -> pid
      nil -> nil
    end
  end

  def lookup(name) when is_object_name(name) do
    case Registry.lookup(__MODULE__, String.downcase(name)) do
      [{pid, value}] -> {pid, value}
      [] -> nil
    end
  end

  defp canonical(name) when is_binary(name), do: String.downcase(name)
  defp canonical(name) when name in @special_names, do: name
end
