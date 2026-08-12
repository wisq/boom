defmodule Boom.Command do
  @enforce_keys [:type, :origin, :target]
  defstruct(
    id: nil,
    type: nil,
    params: nil,
    origin: nil,
    target: nil
  )

  import Boom.ObjectRegistry, only: [is_object_name: 1]
  alias __MODULE__
  alias Boom.Grid.Block

  def get_origin_version(%Command{origin: %Block{}}), do: 1

  def get_origin_version(%Command{origin: name}) when is_object_name(name),
    do: Boom.ObjectRegistry.version(name)

  def build_geometry(%Command{type: module} = command) do
    module.build_geometry(command)
  end
end
