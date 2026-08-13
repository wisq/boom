defmodule Boom.DB.Repo.Migrations.PopulateSubdivisions do
  use Ecto.Migration
  alias Boom.DB.Repo
  import Ecto.Query, only: [from: 2]

  @minor_columns 0..9//1
  @minor_rows 9..0//-1
  @global_scale 10

  @grid_height Enum.count(@minor_rows) * @global_scale
  @geometry_scale 100

  def up do
    Repo.transaction(fn ->
      from(s in "sectors",
        select: [:id, :name, :x, :y],
        order_by: :id
      )
      |> Repo.all()
      |> Enum.flat_map(fn %{id: sector_id, name: sector_name, x: sector_x, y: sector_y} ->
        @minor_columns
        |> Enum.with_index()
        |> Enum.flat_map(fn {column, local_x} ->
          @minor_rows
          |> Enum.with_index()
          |> Enum.map(fn {row, local_y} ->
            global_x = sector_x * @global_scale + local_x
            global_y = sector_y * @global_scale + local_y

            %{
              name: "#{sector_name} #{column}:#{row}",
              sector_id: sector_id,
              local_x: local_x,
              local_y: local_y,
              global_x: global_x,
              global_y: global_y,
              geom: square(global_x, global_y)
            }
          end)
        end)
      end)
      |> Enum.chunk_every(7000)
      |> Enum.each(&Repo.insert_all("subdivisions", &1))
    end)
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
