defmodule Boom.DB.GeoEngine do
  require Logger
  import Boom.Guards
  import Ecto.Query, only: [from: 2]

  alias Boom.DB.Repo
  alias Boom.DB

  def bounding_boxes(%Geo.Point{coordinates: c}), do: [bbox_coords([c])]
  def bounding_boxes(%Geo.LineString{coordinates: c}), do: [bbox_coords(c)]
  def bounding_boxes(%Geo.Polygon{coordinates: [outer | _]}), do: [bbox_coords(outer)]

  def bounding_boxes(%Geo.MultiPolygon{} = multi) do
    multi
    |> split_multipolygon()
    |> Enum.flat_map(&bounding_boxes/1)
  end

  defp bbox_coords(coords) do
    {xs, ys} = Enum.unzip(coords)
    {Enum.min_max(xs), Enum.min_max(ys)}
  end

  def in_bounds?({x, y}, {{xmin, xmax}, {ymin, ymax}}) do
    x >= xmin && x <= xmax && y >= ymin && y <= ymax
  end

  def in_bounds?({x, y}, boxes) when is_list(boxes) do
    boxes |> Enum.any?(&in_bounds?({x, y}, &1))
  end

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
      %{coordinates: []} -> :disjoint
      %{coordinates: nil} -> :disjoint
      geometry -> geometry
    end)
  end

  @filter_intersects_sql """
  SELECT
    id
  FROM unnest(
    ?::integer[],
    ?::geometry[]
  ) AS inputs(id, geom)
  WHERE ST_Intersects(geom, ?::geometry)
  """

  def filter_intersects(list, filter_geom, extract_fun \\ &elem(&1, 1))
  def filter_intersects([], _, _), do: []

  def filter_intersects(list, filter_geom, extract_fun)
      when is_list(list) and is_geometry(filter_geom) do
    indexed = list |> Enum.with_index()

    {id_list, geom_list} =
      indexed
      |> Enum.map(fn {item, index} -> {index, extract_fun.(item)} end)
      |> Enum.unzip()

    matching =
      from(
        q in fragment(
          @filter_intersects_sql,
          ^id_list,
          ^geom_list,
          ^filter_geom
        ),
        select: fragment("id")
      )
      |> Repo.all()
      |> MapSet.new()

    indexed
    |> Enum.filter(fn {_, index} ->
      index in matching
    end)
    |> Enum.map(&elem(&1, 0))
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

  def area(geom) do
    from(
      q in fragment("SELECT ST_Area(?::geometry) AS area", ^geom),
      select: fragment("area")
    )
    |> Repo.one()
  end

  def centroid(geom) do
    from(
      q in fragment("SELECT ST_Centroid(?::geometry) AS centroid", ^geom),
      select: fragment("centroid")
    )
    |> Repo.one()
  end

  def centroid_grid_intersection(geom) do
    from(
      s in DB.Subdivision,
      where: fragment("ST_Intersects(?, ST_Centroid(?::geometry))", s.geom, ^geom),
      select: {s.global_x, s.global_y}
    )
    |> Repo.one()
    |> then(fn
      {x, y} ->
        {:ok, block} = Boom.Grid.subdivision_at(x, y)
        block

      nil ->
        nil
    end)
  end

  def buffer(geom, amount) do
    from(
      q in fragment(
        "SELECT ST_Buffer(?::geometry, ?::double precision) AS buffed",
        ^geom,
        ^amount
      ),
      select: fragment("buffed")
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

  @median_sql """
  (
    WITH grid AS (
      SELECT (ST_HexagonGrid(?::double precision, ?::geometry)).geom AS cell_geom
    ),
    points AS (
      SELECT ST_Centroid(grid.cell_geom) AS pt_geom
      FROM grid
      WHERE ST_Intersects(ST_Centroid(grid.cell_geom), ?::geometry)
    )
    SELECT ST_GeometricMedian(ST_Collect(pt_geom)) AS median
    FROM points
  )
  """

  @min_grid_size 0.1

  def median(geom, size \\ 10.0) when size >= @min_grid_size do
    from(
      q in fragment(@median_sql, ^size, ^geom, ^geom),
      select: fragment("median")
    )
    |> Repo.one()
    |> then(fn
      nil ->
        if size <= @min_grid_size do
          raise "No median found: #{inspect(geom)}"
        else
          new_size = (size / 2) |> max(@min_grid_size)
          Logger.warning("No geometric median, trying size #{new_size} ...")
          median(geom, new_size)
        end

      %Geo.Point{} = p ->
        p
    end)
  end

  @subdivisions_sql """
  SELECT
      sec.name AS sector_name,
      COUNT(sub.id) AS sub_count
  FROM subdivisions sub
  INNER JOIN sectors sec ON sub.sector_id = sec.id
  WHERE ST_Intersects(sub.geom, ?::geometry)
  GROUP BY sector_name
  """

  def count_grid_intersections_by_sector(geom) do
    from(
      q in fragment(@subdivisions_sql, ^geom),
      select: [fragment("sector_name"), fragment("sub_count")]
    )
    |> Repo.all()
    |> Enum.map(fn [name, count] -> {name, count} end)
  end

  def grid_intersections(geom) do
    from(s in DB.Subdivision,
      where: fragment("ST_Intersects(?, ?::geometry)", s.geom, ^geom)
    )
    |> Repo.all()
  end
end
