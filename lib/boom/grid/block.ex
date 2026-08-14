defmodule Boom.Grid.Block do
  @enforce_keys [:name, :index, :extents]
  defstruct(
    name: nil,
    index: nil,
    extents: nil,
    geometry: nil
  )

  alias __MODULE__
  alias Boom.Grid
  alias Boom.DB

  def from_db(%DB.Sector{} = sector) do
    {{x_min, y_min}, {x_max, y_max}} =
      sector.subdivisions
      |> Enum.map(fn s -> {s.global_x, s.global_y} end)
      |> Enum.min_max()

    sector_block = %Block{
      name: sector.name,
      index: {sector.x, sector.y},
      extents: {
        x_min..x_max,
        y_min..y_max
      },
      geometry: sector.geom
    }

    subdivision_blocks = sector.subdivisions |> Enum.map(&from_db/1)

    {sector_block, subdivision_blocks}
  end

  def from_db(%DB.Subdivision{global_x: x, global_y: y} = sub) do
    %Block{
      name: sub.name,
      index: {x, y},
      extents: {
        x..x,
        y..y
      },
      geometry: sub.geom
    }
  end

  def square({x1, y1}, {x2, y2}) do
    %Geo.Polygon{
      coordinates: [
        [
          {x1, y1},
          {x1, y2},
          {x2, y2},
          {x2, y1},
          {x1, y1}
        ]
      ]
    }
  end

  def geo_coord_to_grid({x, y}) do
    {_grid_width, grid_height} = Grid.grid_size()
    geometry_scale = Grid.geometry_scale()

    {
      x / geometry_scale,
      grid_height - y / geometry_scale
    }
  end
end
