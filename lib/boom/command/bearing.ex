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

  # max_dist of 30km is chosen to ensure that even a 45°-error (i.e.
  # right-angled) triangle will always extend off one of the sides of the map,
  # without the hypotenuse ever re-entering the grid.
  #
  # This WILL NOT WORK if you start going too far above 45°.  But that's fine,
  # because we assume that "target is to the east of spotter" means it's more
  # east than north/south (i.e. between 45° and 135°), or else they would've
  # said "target is to the north/south of spotter" instead.
  #
  # If we ever need a literal "target is somewhere to the east" operator (any
  # angle between 0° and 180°), that will be a separate command with a (much
  # simpler) geometry calculation.

  @sql """
  (WITH config AS (
      SELECT 
          ?::double precision AS angle_x,
          ?::double precision AS angle_y,
          30000 AS max_dist
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

  def command_text(%Command{
        type: __MODULE__,
        target: target,
        params: {bearing, error},
        origin: origin
      }) do
    "#{target} is #{direction_text(bearing, error)} from #{origin_text(origin)}"
  end

  defp direction_text(+0.0, 45.0), do: "due north"
  defp direction_text(90.0, 45.0), do: "due east"
  defp direction_text(180.0, 45.0), do: "due south"
  defp direction_text(270.0, 45.0), do: "due west"

  defp direction_text(45.0, 22.5), do: "due northeast"
  defp direction_text(135.0, 22.5), do: "due southeast"
  defp direction_text(225.0, 22.5), do: "due southwest"
  defp direction_text(315.0, 22.5), do: "due northwest"

  defp direction_text(22.5, 11.25), do: "due north-northeast"
  defp direction_text(67.5, 11.25), do: "due east-northeast"
  defp direction_text(112.5, 11.25), do: "due east-southeast"
  defp direction_text(157.5, 11.25), do: "due south-southeast"
  defp direction_text(202.5, 11.25), do: "due south-southwest"
  defp direction_text(247.5, 11.25), do: "due west-southwest"
  defp direction_text(292.5, 11.25), do: "due west-northwest"
  defp direction_text(337.5, 11.25), do: "due north-northwest"

  defp direction_text(bearing, error) do
    "bearing #{bearing}° ± #{error}°"
  end

  defp origin_text(%Block{name: name}), do: name
  defp origin_text(name) when is_object_name(name), do: name
end
