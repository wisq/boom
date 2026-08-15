defmodule Boom.Command do
  @enforce_keys [:type, :origin, :target]
  defstruct(
    id: nil,
    type: nil,
    params: nil,
    origin: nil,
    target: nil,
    active: true
  )

  import Boom.ObjectRegistry, only: [is_object_name: 1, is_geom_error: 1]
  alias __MODULE__
  alias Boom.Grid.Block
  alias Boom.ObjectRegistry

  def get_origin_version(%Command{origin: %Block{}}), do: 1

  def get_origin_version(%Command{origin: name}) when is_object_name(name),
    do: ObjectRegistry.version(name)

  def build_geometry(%Command{type: module, origin: %Block{geometry: geom}} = command) do
    module.build_geometry(command, geom)
  end

  def build_geometry(%Command{type: module, origin: name} = command) when is_object_name(name) do
    case ObjectRegistry.geometry(name) do
      err when is_geom_error(err) -> err
      geom when is_struct(geom) -> module.build_geometry(command, geom)
    end
  end

  defimpl String.Chars do
    def to_string(%Command{id: id, type: module} = command) do
      "#{inspect(id)}: #{module.command_text(command)}"
    end
  end
end
