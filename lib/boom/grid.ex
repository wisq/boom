defmodule Boom.Grid do
  # Left-to-right, top-to-bottom:
  @major_columns ?A..?T |> Enum.map(&<<&1>>)
  @major_rows 10..1//-1
  @minor_columns 0..9//1
  @minor_rows 9..0//-1

  @grid_size {
    Enum.count(@major_columns) * Enum.count(@minor_columns),
    Enum.count(@major_rows) * Enum.count(@minor_rows)
  }

  @sectors @major_columns
           |> Enum.with_index()
           |> Enum.flat_map(fn {column, x} ->
             @major_rows
             |> Enum.with_index()
             |> Enum.map(fn {row, y} ->
               {"#{column}#{row}", {x, y}}
             end)
           end)
           |> Map.new()
           |> IO.inspect()

  def major_columns, do: @major_columns
  def minor_columns, do: @minor_columns
  def major_rows, do: @major_rows
  def minor_rows, do: @minor_rows
  def sectors, do: @sectors
  def grid_size, do: @grid_size
end
