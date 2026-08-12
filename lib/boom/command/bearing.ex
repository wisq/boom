defmodule Boom.Command.Bearing do
  alias Boom.Grid.Block
  alias Boom.Command

  import Boom.ObjectRegistry, only: [is_object_name: 1]
  defguard is_block(b) when is_struct(b, Block)
  defguard is_origin(o) when is_object_name(o) or is_block(o)

  def new(bearing, error, origin, target)
      when is_number(bearing) and is_number(error) and
             is_origin(origin) and is_object_name(target) do
    %Command{
      type: __MODULE__,
      params: {bearing, error},
      origin: origin,
      target: target
    }
  end

  import Ecto.Query, only: [from: 2]
  alias Boom.GeoEngine, as: Repo

  @sql """
  (WITH config AS (
      SELECT 
          ?::double precision AS angle_x,
          ?::double precision AS angle_y,
          25000 AS max_dist
  ),
  triangle AS (
      -- Triangle wedge from X to Y degrees, starting at origin:
      SELECT ST_MakePolygon(ST_MakeLine(ARRAY[
          ST_MakePoint(0, 0),
          ST_MakePoint(max_dist * sin(radians(angle_x)), max_dist * cos(radians(angle_x))),
          ST_MakePoint(max_dist * sin(radians(angle_y)), max_dist * cos(radians(angle_y))),
          ST_MakePoint(0, 0)
      ])) AS triangle_geom
      FROM config
  )
  SELECT 
      CG_MinkowskiSum(?::geometry, triangle_geom) AS target FROM triangle
  )
  """

  def build_geometry(%Command{type: __MODULE__, params: {bearing, error}}, geom) do
    min_angle = bearing - error
    max_angle = bearing + error

    from(
      q in fragment(
        @sql,
        ^min_angle,
        ^max_angle,
        ^geom
      ),
      select: fragment("target")
    )
    |> Repo.one()
  end
end
