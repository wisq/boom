defmodule Boom.DB.Repo.Migrations.TargetAreaCovered do
  use Ecto.Migration

  @sql """
  CREATE OR REPLACE FUNCTION target_area_covered(
      ownship_geom      geometry,
      target_geom       geometry,
      offset_x          double precision,
      offset_y          double precision,
      blast_radius      double precision,
      grid_step         double precision DEFAULT 10.0,
      circle_segments   integer          DEFAULT 64
  )
  RETURNS double precision
  LANGUAGE plpgsql
  IMMUTABLE
  PARALLEL SAFE
  AS $$
  DECLARE
      average_area_hit   double precision;
  BEGIN
      WITH 
      ownship_grid AS (
          SELECT ST_Centroid(grid.geom) AS point
          FROM ST_HexagonGrid(grid_step, ownship_geom) AS grid
          WHERE ST_Intersects(grid.geom, ownship_geom)
      ),
      projected_grid AS (
          SELECT ST_MakePoint(
            ST_X(pg.point) + offset_x,
            ST_Y(pg.point) + offset_y
          ) AS point
          FROM ownship_grid pg
      ),
      blast_circles AS (
          SELECT ST_Buffer(projected_grid.point, blast_radius) AS geom
          FROM projected_grid
      ),
      target_area_hit AS (
          SELECT ST_Area(ST_Intersection(blast_circles.geom, target_geom)) AS area
          FROM blast_circles 
      )
      SELECT avg(target_area_hit.area)
      FROM target_area_hit
      INTO average_area_hit;

      RETURN average_area_hit;
  END;
  $$;
  """

  def up do
    execute(@sql)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS target_area_covered")
  end
end
