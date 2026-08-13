defmodule Boom.DB.Repo.Migrations.PopulateSectors do
  use Ecto.Migration
  alias Boom.DB.Repo

  @major_columns ?A..?T |> Enum.map(&<<&1>>)
  @major_rows 10..1//-1

  @grid_height 10
  @geometry_scale 1000

  def up do
    @major_columns
    |> Enum.with_index()
    |> Enum.flat_map(fn {column, x} ->
      @major_rows
      |> Enum.with_index()
      |> Enum.map(fn {row, y} ->
        %{
          name: "#{column}#{row}",
          x: x,
          y: y,
          geom: square(x, y)
        }
      end)
    end)
    |> then(&Repo.insert_all("sectors", &1))
  end

  defp square(x, y) do
    {x1, y1} = grid_to_geo_coord(x, y)
    {x2, y2} = grid_to_geo_coord(x + 1, y + 1)

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

  defp grid_to_geo_coord(x, y) do
    {
      x * @geometry_scale,
      (@grid_height - y) * @geometry_scale
    }
    |> then(fn {x, y} when x in 0..20000 and y in 0..10000 -> {x, y} end)
  end
end
