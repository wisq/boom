defmodule Boom.Object do
  use GenServer
  require Logger

  alias Boom.ObjectRegistry
  alias Boom.Command
  alias Boom.CommandLog
  alias Boom.Grid
  alias Boom.DB.GeoEngine
  import Boom.ObjectRegistry, only: [is_object_name: 1]

  defmodule State do
    @enforce_keys [:name, :title]
    defstruct(
      name: nil,
      title: nil,
      version: 0,
      depends_on: MapSet.new(),
      cache: %{}
    )
  end

  defmodule CacheEntry do
    @enforce_keys [:command_id]
    defstruct(
      command_id: nil,
      version: -1,
      origin: nil,
      geometry: :pending,
      changed: false
    )

    def update(
          %CacheEntry{command_id: id, version: old_version, geometry: old_geometry} = entry,
          %Command{id: id, origin: origin} = command
        ) do
      new_version = Command.get_origin_version(command)

      if new_version != old_version do
        new_geometry = Command.build_geometry(command)

        %CacheEntry{
          command_id: id,
          version: new_version,
          origin: origin,
          geometry: new_geometry,
          changed: new_geometry != old_geometry
        }
      else
        %CacheEntry{entry | changed: false}
      end
    end

    def update(nil, %Command{id: id} = command) do
      update(%CacheEntry{command_id: id}, command)
    end
  end

  def child_spec(name) do
    super(object_name: name)
    |> Map.put(:restart, :temporary)
  end

  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :object_name)
    GenServer.start_link(__MODULE__, name, opts)
  end

  @impl true
  def init(name) do
    with {:ok, _} <- ObjectRegistry.register(name) do
      PubSub.subscribe(self(), :object_registry)
      PubSub.subscribe(self(), :command_log)
      send(self(), :recalculate)
      {:ok, %State{name: name, title: generate_title(name)}}
    end
  end

  @impl true
  def handle_info(:recalculate, %State{name: name, title: title} = state) do
    entries =
      CommandLog.active_entries(name)
      |> with_cache(state.cache)
      |> Enum.map(fn {command, entry} -> CacheEntry.update(entry, command) end)

    depends_on =
      entries
      |> Enum.map(& &1.origin)
      |> Enum.filter(&is_object_name/1)
      |> MapSet.new()

    cache =
      entries
      |> Map.new(&{&1.command_id, &1})

    state = %State{state | depends_on: depends_on, cache: cache}

    if Enum.any?(entries, &{&1.changed}) do
      geometry =
        entries
        |> Enum.map(& &1.geometry)
        |> build_geometry()

      if geometry == ObjectRegistry.geometry(name) do
        Boom.output([title, ": Geometry is unchanged."])
        Logger.info(log_prefix(state) <> "Geometry is unchanged.")
        {:noreply, state}
      else
        version = state.version + 1

        case describe_geometry(geometry, cache) do
          :silent -> :noop
          iodata -> Boom.output([title, ": ", iodata])
        end

        ObjectRegistry.update(name, version, geometry)
        Logger.info(log_prefix(state) <> "Updated to version #{version}.")

        {:noreply, %State{state | version: version}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:object_updated, name}, %State{name: name} = state), do: {:noreply, state}

  @impl true
  def handle_info({:object_updated, name}, %State{depends_on: deps} = state) do
    if name in deps do
      Logger.debug(log_prefix(state) <> "Recalculating due to object #{inspect(name)} change")
      send(self(), :recalculate)
    end

    {:noreply, state}
  end

  @imp @impl true
  def handle_info({:command_added, name}, %State{name: name} = state) do
    Logger.debug(log_prefix(state) <> "Recalculating due to added command")
    send(self(), :recalculate)
    {:noreply, state}
  end

  @impl true
  def handle_info({:command_added, _}, state), do: {:noreply, state}

  defp with_cache(commands, cache) do
    commands
    |> Enum.map(&{&1, Map.get(cache, &1)})
  end

  defp build_geometry([]), do: :unknown

  defp build_geometry([_ | _] = geoms) do
    geoms
    |> Enum.reduce_while(Grid.grid_geometry(), fn
      :pending, _ -> {:halt, :pending}
      :unknown, _ -> {:halt, :unknown}
      _, :disjoint -> {:halt, :disjoint}
      %{} = geom, %{} = acc -> {:cont, GeoEngine.intersection(geom, acc)}
    end)
  end

  defp log_prefix(%State{name: name}) do
    "[#{inspect(__MODULE__)} #{inspect(name)}] "
  end

  defp describe_geometry(:unknown, cache) do
    cache
    |> Map.values()
    |> Enum.filter(&(&1.geometry == :unknown))
    |> Enum.map(fn entry -> entry.origin |> origin_name() end)
    |> then(fn deps ->
      ["Waiting on geometry data for ", comma_list(deps), "."]
    end)
  end

  # Unless there's a bug, this should be a very temporary condition.
  defp describe_geometry(:pending, _), do: :silent

  defp describe_geometry(:disjoint, _) do
    ["Geometry is impossible!  All positions have been ruled out."]
  end

  defp describe_geometry(%Geo.Polygon{} = polygon, _) do
    ["Location ", describe_polygon(polygon), "."]
  end

  defp describe_geometry(%Geo.MultiPolygon{} = multi, _) do
    [
      "Multiple possible locations:",
      multi
      |> GeoEngine.split_multipolygon()
      |> Enum.with_index(1)
      |> Enum.map(fn {poly, index} ->
        ["\n    Location #{index} ", describe_polygon(poly), "."]
      end)
    ]
  end

  defp comma_list(list, and_or \\ "and")
  defp comma_list([a], _), do: a
  defp comma_list([a, b], and_or), do: [a, " ", and_or, " ", b]

  defp comma_list(more, and_or) do
    {head, last} = more |> Enum.split(-1)

    head
    |> Enum.intersperse(", ")
    |> Kernel.++([", ", and_or, " ", last])
  end

  defp count_cells(1), do: "one"
  defp count_cells(2), do: "two"
  defp count_cells(3), do: "three"
  defp count_cells(4), do: "four"
  defp count_cells(5), do: "five"
  defp count_cells(6), do: "six"
  defp count_cells(7), do: "seven"
  defp count_cells(8), do: "eight"
  defp count_cells(9), do: "nine"
  defp count_cells(10), do: "ten"
  defp count_cells(11), do: "eleven"
  defp count_cells(12), do: "twelve"
  defp count_cells(13), do: "thirteen"
  defp count_cells(14), do: "fourteen"
  defp count_cells(15), do: "fifteen"
  defp count_cells(16), do: "sixteen"
  defp count_cells(17), do: "seventeen"
  defp count_cells(18), do: "eighteen"
  defp count_cells(19), do: "nineteen"
  defp count_cells(20), do: "twenty"

  defp generate_title(:ownship), do: "Iron Nest"
  defp generate_title(name), do: :string.titlecase(name)

  defp origin_name(:ownship), do: "Iron Nest"
  defp origin_name(name), do: name

  defp describe_polygon(%Geo.Polygon{} = polygon) do
    ints_by_sector = GeoEngine.count_grid_intersections_by_sector(polygon)
    sectors = Enum.count(ints_by_sector)
    total_subs = ints_by_sector |> Enum.sum_by(fn {_, count} -> count end)

    cond do
      total_subs == 1 ->
        [sub] = GeoEngine.grid_intersections(polygon)
        ["is ", sub.name]

      total_subs <= 5 ->
        subs =
          GeoEngine.grid_intersections(polygon)
          |> Enum.sort_by(&{&1.global_x, &1.global_y})
          |> Enum.map(& &1.name)

        ["is in one of ", comma_list(subs, "or")]

      sectors > 3 ->
        "spans #{total_subs} grid squares across #{sectors} sectors"

      sectors > 1 ->
        by_sec =
          ints_by_sector
          |> Enum.map(fn {name, count} ->
            [count_cells(count), " in ", name]
          end)

        ["spans #{total_subs} grid squares: ", comma_list(by_sec)]

      total_subs > 1 ->
        [{name, _}] = ints_by_sector
        "is in one of #{total_subs} grid squares in sector #{name}"

      true ->
        "whee"
    end
  end
end
