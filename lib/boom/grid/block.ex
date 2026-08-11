defmodule Boom.Grid.Block do
  @enforce_keys [:name, :index, :extents]
  defstruct(
    name: nil,
    index: nil,
    extents: nil,
    geometry: nil
  )

  alias __MODULE__

  # Left-to-right, top-to-bottom:
  @major_columns ?A..?T |> Enum.map(&<<&1>>)
  @major_rows 10..1//-1
  @minor_columns 0..9//1
  @minor_rows 9..0//-1

  @major_column_count Enum.count(@major_columns)
  @minor_column_count Enum.count(@minor_columns)
  @major_row_count Enum.count(@major_rows)
  @minor_row_count Enum.count(@minor_rows)

  @grid_size {
    Enum.count(@major_columns) * Enum.count(@minor_columns),
    Enum.count(@major_rows) * Enum.count(@minor_rows)
  }
  def grid_size, do: @grid_size

  # 100m per minor block side
  @geometry_size 100.0

  def major_coords do
    0..(@major_column_count - 1)
    |> Enum.flat_map(fn x ->
      0..(@major_row_count - 1)
      |> Enum.map(fn y -> {x, y} end)
    end)
  end

  def minor_coords do
    0..(@minor_column_count - 1)
    |> Enum.flat_map(fn x ->
      0..(@minor_row_count - 1)
      |> Enum.map(fn y -> {x, y} end)
    end)
  end

  def major({x, y}) do
    column = Enum.at(@major_columns, x)
    row = Enum.at(@major_rows, y)

    global_x_min = x * @minor_column_count
    global_y_min = y * @minor_column_count
    global_x_max = global_x_min + @minor_column_count - 1
    global_y_max = global_y_min + @minor_column_count - 1

    %Block{
      name: "#{column}#{row}",
      index: {x, y},
      extents: {
        global_x_min..global_x_max,
        global_y_min..global_y_max
      }
    }
    |> add_geometry()
  end

  def minor(%Block{} = sector, {local_x, local_y}) do
    column = Enum.at(@minor_columns, local_x)
    row = Enum.at(@minor_rows, local_y)

    {global_x_offset.._//_, global_y_offset.._//_} = sector.extents
    global_x = global_x_offset + local_x
    global_y = global_y_offset + local_y

    %Block{
      name: "#{sector.name} #{column}:#{row}",
      index: {global_x, global_y},
      extents: {
        global_x..global_x,
        global_y..global_y
      }
    }
    |> add_geometry()
  end

  def add_geometry(%Block{extents: {x1..x2//_, y1..y2//_}} = block) do
    x1 = x1 * @geometry_size
    y1 = y1 * @geometry_size
    x2 = (x2 + 1) * @geometry_size
    y2 = (y2 + 1) * @geometry_size

    %Block{
      block
      | geometry: %Geo.Polygon{
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
    }
  end
end
