defmodule Boom.GeoEngine.Migrations.RangeRing do
  use Ecto.Migration

  @sql """
  -- Returns the set of points reachable from ANY point of `geom` at a
  -- distance between min_dist and max_dist (inclusive), i.e. the union
  -- of annuli [min_dist, max_dist] centered at every point of geom.
  --
  -- Cannot be run on multipolygons -- those must be split first.

  CREATE OR REPLACE FUNCTION range_ring(
      geom      geometry,
      min_dist  double precision,
      max_dist  double precision,
      quad_segs int DEFAULT 16
  ) RETURNS geometry AS $$
  DECLARE
      outer_region geometry;
      inner_region geometry;
      hull_pts     geometry[];
      pt           geometry;
  BEGIN
      -- Everything within max_dist of the polygon.
      outer_region := ST_Buffer(geom, max_dist, quad_segs);

      IF min_dist = 0 THEN
          RETURN outer_region;
      END IF;

      -- The "far point" for any external p is always a vertex of the
      -- convex hull (distance is a convex function of q), so we only
      -- need to intersect disks centered at hull vertices.
      SELECT array_agg((d).geom)
        INTO hull_pts
        FROM ST_DumpPoints(ST_ConvexHull(geom)) AS d;

      inner_region := NULL;
      FOREACH pt IN ARRAY hull_pts LOOP
          IF inner_region IS NULL THEN
              inner_region := ST_Buffer(pt, min_dist, quad_segs);
          ELSE
              inner_region := ST_Intersection(inner_region, ST_Buffer(pt, min_dist, quad_segs));
          END IF;

          -- Short-circuit: once empty, it stays empty.
          IF inner_region IS NULL OR ST_IsEmpty(inner_region) THEN
              inner_region := ST_GeomFromText('POLYGON EMPTY', ST_SRID(geom));
              EXIT;
          END IF;
      END LOOP;

      -- inner_region is non-empty only when the whole polygon fits
      -- inside a circle of radius min_dist (i.e. min_dist is large
      -- relative to the polygon's size) — that's the only case where
      -- points get excluded near the "center".
      IF ST_IsEmpty(inner_region) THEN
          RETURN outer_region;
      ELSE
          RETURN ST_Difference(outer_region, inner_region);
      END IF;
  END;
  $$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;
  """

  def up do
    execute(@sql)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS range_ring")
  end
end
