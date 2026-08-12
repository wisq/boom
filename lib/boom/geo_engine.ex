defmodule Boom.GeoEngine do
  use Ecto.Repo,
    otp_app: :boom,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query, only: [from: 2]

  alias __MODULE__, as: Repo

  def intersection(geom_a, geom_b) do
    from(
      q in fragment(
        "SELECT ST_Intersection(?::geometry, ?::geometry) AS geom",
        ^geom_a,
        ^geom_b
      ),
      select: fragment("geom")
    )
    |> Repo.one()
    |> then(fn
      %Geo.Polygon{coordinates: []} -> :disjoint
      geometry -> geometry
    end)
  end

  def union(geom_a, geom_b) do
    from(
      q in fragment(
        "SELECT ST_Union(?::geometry, ?::geometry) AS geom",
        ^geom_a,
        ^geom_b
      ),
      select: fragment("geom")
    )
    |> Repo.one()
  end

  @bounding_sql """
  SELECT
      ST_Centroid(circle) AS aim_point,
      ST_Distance(
          ST_Centroid(circle),
          ST_PointN(ST_ExteriorRing(circle), 1)
      ) AS radius
  FROM (
      SELECT ST_MinimumBoundingCircle(?::geometry) AS circle
  )
  """

  def min_bounding_circle(geom) do
    from(
      q in fragment(@bounding_sql, ^geom),
      select: [fragment("radius"), fragment("aim_point")]
    )
    |> Repo.one()
    |> then(fn [radius, aim_point] -> {radius, aim_point} end)
  end

  def split_multipolygon(%Geo.MultiPolygon{coordinates: polys}) do
    polys
    |> Enum.map(&%Geo.Polygon{coordinates: &1})
  end

  def split_multipolygon(%Geo.Polygon{} = poly), do: [poly]
end
