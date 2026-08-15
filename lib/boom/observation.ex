defmodule Boom.Observation do
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
  alias __MODULE__, as: Obs
  alias Boom.Grid.Block
  alias Boom.ObjectRegistry

  def get_origin_version(%Obs{origin: %Block{}}), do: 1

  def get_origin_version(%Obs{origin: name}) when is_object_name(name),
    do: ObjectRegistry.version(name)

  def build_geometry(%Obs{type: module, origin: %Block{geometry: geom}} = obs) do
    module.build_geometry(obs, geom)
  end

  def build_geometry(%Obs{type: module, origin: name} = obs) when is_object_name(name) do
    case ObjectRegistry.geometry(name) do
      err when is_geom_error(err) -> err
      geom when is_struct(geom) -> module.build_geometry(obs, geom)
    end
  end

  defimpl String.Chars do
    def to_string(%Obs{id: id, type: module} = obs) do
      "#{inspect(id)}: #{module.command_text(obs)}"
    end
  end
end
