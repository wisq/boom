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

  def sectors, do: @sectors
  def subdivisions, do: @subdivisions
  defdelegate grid_size, to: Block

  def subdivision_at(x, y), do: Map.fetch(@subs_by_extent, {x, y})
end
