defmodule Boom.Grid do
  alias Boom.Grid.Block

  @sectors __MODULE__.Sectors
  @subdivisions __MODULE__.Subdivisions
  @grid_geometry __MODULE__.GridGeometry
  @subs_by_extent __MODULE__.SubsByExtent
  @blocks_by_name __MODULE__.BlocksByName

  def init do
    unless :persistent_term.get(__MODULE__, nil) == :loaded, do: build()
  end

  def build do
    sectors =
      Block.major_coords()
      |> Enum.map(&Block.major/1)

    subdivisions =
      sectors
      |> Enum.flat_map(fn sector ->
        Block.minor_coords() |> Enum.map(&Block.minor(sector, &1))
      end)

    {corner1, corner2} =
      sectors
      |> Enum.flat_map(fn %Block{geometry: %Geo.Polygon{coordinates: [coords]}} -> coords end)
      |> Enum.min_max()

    grid_geometry = Block.square(corner1, corner2)

    blocks_by_name = Map.new(sectors ++ subdivisions, &{&1.name, &1})

    subs_by_extent =
      Map.new(subdivisions, fn %Block{extents: {x..x//_, y..y//_}} = block ->
        {{x, y}, block}
      end)

    :persistent_term.put(@sectors, sectors)
    :persistent_term.put(@subdivisions, subdivisions)
    :persistent_term.put(@grid_geometry, grid_geometry)
    :persistent_term.put(@subs_by_extent, subs_by_extent)
    :persistent_term.put(@blocks_by_name, blocks_by_name)
    :persistent_term.put(__MODULE__, :loaded)
    :ok
  end

  def sectors, do: :persistent_term.get(@sectors)
  def subdivisions, do: :persistent_term.get(@subdivisions)
  def grid_geometry, do: :persistent_term.get(@grid_geometry)
  defdelegate grid_size, to: Block

  def subdivision_at(x, y), do: :persistent_term.get(@subs_by_extent) |> Map.fetch({x, y})

  def block_by_name(name),
    do: :persistent_term.get(@blocks_by_name) |> Map.fetch(String.upcase(name))
end
