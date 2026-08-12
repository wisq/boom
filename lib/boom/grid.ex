defmodule Boom.Grid do
  alias Boom.Grid.Block

  @sectors Block.major_coords() |> Enum.map(&Block.major/1)
  @subdivisions @sectors
                |> Enum.flat_map(fn sector ->
                  Block.minor_coords() |> Enum.map(&Block.minor(sector, &1))
                end)

  @subs_by_extent Map.new(@subdivisions, fn %Block{extents: {x..x//_, y..y//_}} = block ->
                    {{x, y}, block}
                  end)

  {corner1, corner2} =
    @sectors
    |> Enum.flat_map(fn %Block{geometry: %Geo.Polygon{coordinates: [coords]}} -> coords end)
    |> Enum.min_max()

  @grid_geometry Block.square(corner1, corner2)

  def sectors, do: @sectors
  def subdivisions, do: @subdivisions
  def grid_geometry, do: @grid_geometry
  defdelegate grid_size, to: Block

  def subdivision_at(x, y), do: Map.fetch(@subs_by_extent, {x, y})
end
