defmodule Boom.Command.Range do
  alias Boom.Grid.Block
  alias Boom.Command

  import Boom.ObjectRegistry, only: [is_object_name: 1]
  defguard is_block(b) when is_struct(b, Block)
  defguard is_origin(o) when is_object_name(o) or is_block(o)

  def new(range, error, origin, target)
      when is_number(range) and is_number(error) and
             is_origin(origin) and is_object_name(target) do
    %Command{
      type: __MODULE__,
      params: {range, error},
      origin: origin,
      target: target
    }
  end

  import Ecto.Query, only: [from: 2]
  alias Boom.GeoEngine

  def build_geometry(%Command{type: __MODULE__, params: {range, error}}, geom) do
    min_range = range - error
    max_range = range + error

    from(
      q in fragment(
        "SELECT Range_Ring(?::geometry, ?::double precision, ?::double precision) AS geom",
        ^geom,
        ^min_range,
        ^max_range
      ),
      select: fragment("geom")
    )
    |> GeoEngine.one()
  end
end
