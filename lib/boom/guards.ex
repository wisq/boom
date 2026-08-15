defmodule Boom.Guards do
  @special_object_names Boom.Defines.special_object_names()
  @solution_errors Boom.Defines.solution_errors()

  defguard is_object_name(name) when is_binary(name) or name in @special_object_names

  # There's more geometries than this, but these are the only ones I can see us
  # reasonably supporting.
  defguard is_geometry(g)
           when is_struct(g, Geo.Polygon) or
                  is_struct(g, Geo.MultiPolygon) or
                  is_struct(g, Geo.Point) or
                  is_struct(g, Geo.MultiPoint) or
                  is_struct(g, Geo.LineString)

  defguard is_solution_error(err) when err in @solution_errors
  defguard is_solution(geom) when is_geometry(geom) or is_solution_error(geom)

  defguard is_block(b) when is_struct(b, Boom.Grid.Block)
  defguard is_origin(o) when is_object_name(o) or is_block(o)
end
