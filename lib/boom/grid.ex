defmodule Boom.Grid do
  use GenServer
  alias Boom.DB
  alias Boom.Grid.Block
  import Ecto.Query, only: [from: 2]

  @sectors __MODULE__.Sectors
  @subdivisions __MODULE__.Subdivisions
  @grid_size __MODULE__.GridSize
  @grid_geometry __MODULE__.GridGeometry
  @geometry_scale __MODULE__.GeometryScale
  @subs_by_extent __MODULE__.SubsByExtent
  @blocks_by_name __MODULE__.BlocksByName

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, nil, opts)
  end

  @impl true
  def init(_) do
    {sectors, subdivisions} =
      from(s in DB.Sector, order_by: [desc: s.x, desc: s.y], preload: :subdivisions)
      |> DB.Repo.all()
      |> Enum.reduce({[], []}, fn s, {sec_acc, subs_acc} ->
        {sec, subs} = Block.from_db(s)
        {[sec | sec_acc], subs ++ subs_acc}
      end)

    grid_size =
      from(s in DB.Subdivision, select: {max(s.global_x) + 1, max(s.global_y) + 1})
      |> DB.Repo.one()

    {scale, scale} =
      from(a in DB.Subdivision,
        join: b in DB.Subdivision,
        on: b.global_x == a.global_x + 1 and b.global_y == a.global_y + 1,
        select: {
          fragment("ABS(ROUND((ST_XMin(?) - ST_XMin(?))::numeric, 5))", a.geom, b.geom),
          fragment("ABS(ROUND((ST_YMin(?) - ST_YMin(?))::numeric, 5))", a.geom, b.geom)
        },
        distinct: true
      )
      |> DB.Repo.one()

    geometry_scale = decimal_to_integer(scale)

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
    :persistent_term.put(@grid_size, grid_size)
    :persistent_term.put(@grid_geometry, grid_geometry)
    :persistent_term.put(@geometry_scale, geometry_scale)
    :persistent_term.put(@subs_by_extent, subs_by_extent)
    :persistent_term.put(@blocks_by_name, blocks_by_name)
    {:ok, nil, :hibernate}
  end

  def sectors, do: :persistent_term.get(@sectors)
  def subdivisions, do: :persistent_term.get(@subdivisions)
  def grid_size, do: :persistent_term.get(@grid_size)
  def grid_geometry, do: :persistent_term.get(@grid_geometry)
  def geometry_scale, do: :persistent_term.get(@geometry_scale)

  def subdivision_at(x, y), do: :persistent_term.get(@subs_by_extent) |> Map.fetch({x, y})

  def block_by_name(name),
    do: :persistent_term.get(@blocks_by_name) |> Map.fetch(String.upcase(name))

  def geo_coords_to_grid({x, y}) do
    {_grid_width, grid_height} = grid_size()
    geometry_scale = geometry_scale()

    {
      x / geometry_scale,
      grid_height - y / geometry_scale
    }
  end

  def grid_to_geo_coords({x, y}) do
    {_grid_width, grid_height} = grid_size()
    geometry_scale = geometry_scale()

    {
      x * geometry_scale,
      (grid_height - y) * geometry_scale
    }
  end

  defp decimal_to_integer(decimal) do
    float = Decimal.to_float(decimal)
    int = round(float)

    unless int == float, do: raise("Not a round number: #{inspect(decimal)}")
    int
  end
end
