defmodule Boom.Grid.Block do
  @enforce_keys [:name, :type, :index, :extents]
  defstruct(
    name: nil,
    type: nil,
    index: nil,
    extents: nil,
    geometry: nil
  )

  alias __MODULE__
  alias Boom.DB

  def from_db(%DB.Sector{} = sector) do
    {{x_min, y_min}, {x_max, y_max}} =
      sector.subdivisions
      |> Enum.map(fn s -> {s.global_x, s.global_y} end)
      |> Enum.min_max()

    sector_block = %Block{
      name: sector.name,
      type: :sector,
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
      type: :subdivision,
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

  def within_block(%Block{type: :subdivision} = block, x, y) do
    [[{left, top}, {left, bottom}, {right, bottom} | _]] = block.geometry.coordinates
    unless left < right && bottom < top, do: raise("unexpected geometry")

    x_units = (right - left) / 100
    y_units = (top - bottom) / 100

    x1 = left + x * x_units
    y1 = bottom + y * y_units

    x2 = x1 + x_units
    y2 = y1 + y_units

    %Block{
      name: block.name <> " +#{two_digits(x)}+#{two_digits(y)}",
      type: :within,
      index: nil,
      extents: nil,
      geometry: square({x1, y1}, {x2, y2})
    }
  end

  defp two_digits(n) when n >= 0 and n < 10, do: "0#{n}"
  defp two_digits(n) when n >= 10 and n < 100, do: "#{n}"
end
