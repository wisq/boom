defmodule Boom.Grid do
  use GenServer
  alias Boom.Grid.Block

  @globals __MODULE__.ETS.Globals
  @subs_by_extent __MODULE__.ETS.SubsByExtent
  @blocks_by_name __MODULE__.ETS.BlocksByName

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, nil, opts)
  end

  @impl true
  def init(nil) do
    :ets.new(@globals, [:set, :protected, :named_table, read_concurrency: true])
    :ets.new(@subs_by_extent, [:set, :protected, :named_table, read_concurrency: true])
    :ets.new(@blocks_by_name, [:set, :protected, :named_table, read_concurrency: true])

    sectors = build_sectors()
    subdivisions = build_subdivisions(sectors)

    {corner1, corner2} =
      sectors
      |> Enum.flat_map(fn %Block{geometry: %Geo.Polygon{coordinates: [coords]}} -> coords end)
      |> Enum.min_max()

    grid_geometry = Block.square(corner1, corner2)

    blocks_by_name = Enum.map(sectors ++ subdivisions, &{&1.name, &1})

    subs_by_extent =
      Enum.map(subdivisions, fn %Block{extents: {x..x//_, y..y//_}} = block ->
        {{x, y}, block}
      end)

    :ets.insert(@globals,
      sectors: sectors,
      subdivisions: subdivisions,
      grid_geometry: grid_geometry
    )

    :ets.insert(@subs_by_extent, subs_by_extent)
    :ets.insert(@blocks_by_name, blocks_by_name)
    {:ok, nil}
  end

  def sectors, do: global(:sectors)
  def subdivisions, do: global(:subdivision)
  def grid_geometry, do: global(:grid_geometry)
  defdelegate grid_size, to: Block

  def subdivision_at(x, y) do
    case :ets.lookup(@subs_by_extent, {x, y}) do
      [{{^x, ^y}, block}] -> {:ok, block}
      [] -> :error
    end
  end

  def block_by_name(name) do
    name = String.upcase(name)

    case :ets.lookup(@blocks_by_name, name) do
      [{^name, block}] -> {:ok, block}
      [] -> :error
    end
  end

  def build_sectors do
    Block.major_coords()
    |> Enum.map(&Block.major/1)
  end

  def build_subdivisions(sectors) do
    sectors
    |> Enum.flat_map(fn sector ->
      Block.minor_coords() |> Enum.map(&Block.minor(sector, &1))
    end)
  end

  defp global(key) do
    [{^key, value}] = :ets.lookup(@globals, key)
    value
  end
end
