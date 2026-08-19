defmodule Boom.Object do
  use GenServer
  require Logger
  import Boom.Guards

  alias Boom.ObjectRegistry
  alias Boom.Observation
  alias Boom.ObservationLog
  alias Boom.Grid
  alias Boom.DB.GeoEngine
  alias Boom.Ammo

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
    @enforce_keys [:observation_id]
    defstruct(
      observation_id: nil,
      version: -1,
      origin: nil,
      solution: :pending,
      changed: false
    )

    def update(
          %CacheEntry{observation_id: id, version: old_version, solution: old_solution} = entry,
          %Observation{id: id, origin: origin} = observation
        ) do
      new_version = Observation.get_origin_version(observation)

      if new_version != old_version do
        new_solution = Observation.build_solution(observation)

        %CacheEntry{
          observation_id: id,
          version: new_version,
          origin: origin,
          solution: new_solution,
          changed: new_solution != old_solution
        }
      else
        %CacheEntry{entry | changed: false}
      end
    end

    def update(nil, %Observation{id: id} = observation) do
      update(%CacheEntry{observation_id: id}, observation)
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

  def describe(name) when is_object_name(name) do
    title = object_title(name)

    case ObjectRegistry.solution(name) |> describe_solution(%{}) do
      :silent -> [title, ": Pending."]
      iodata -> format_solution(iodata, title)
    end
  end

  @impl true
  def init(name) do
    with {:ok, _} <- ObjectRegistry.register(name) do
      PubSub.subscribe(self(), :object_registry)
      PubSub.subscribe(self(), :observation_log)
      send(self(), :recalculate)
      {:ok, %State{name: name, title: object_title(name)}}
    end
  end

  @impl true
  def handle_info(:recalculate, %State{name: name, title: title, cache: old_cache} = state) do
    entries =
      ObservationLog.active_entries(name)
      |> with_cache(old_cache)
      |> Enum.map(fn {observation, entry} -> CacheEntry.update(entry, observation) end)

    depends_on =
      entries
      |> Enum.map(& &1.origin)
      |> Enum.filter(&is_object_name/1)
      |> MapSet.new()

    new_cache =
      entries
      |> Map.new(&{&1.observation_id, &1})

    state = %State{state | depends_on: depends_on, cache: new_cache}

    if Enum.any?(entries, &{&1.changed}) || different_keys?(old_cache, new_cache) do
      solution =
        entries
        |> Enum.map(& &1.solution)
        |> build_solution()

      if solution == ObjectRegistry.solution(name) do
        Boom.output([title, ": Geometry is unchanged."])
        Logger.info(log_prefix(state) <> "Geometry is unchanged.")
        {:noreply, state}
      else
        version = state.version + 1

        describe_solution(solution, new_cache)
        |> then(fn
          :silent -> :noop
          iodata -> format_solution(iodata, title) |> Boom.output()
        end)

        ObjectRegistry.update(name, version, solution)
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

  @impl true
  def handle_info({:observation_added, obj_name}, %State{name: my_name} = state) do
    if obj_name == my_name do
      Logger.debug(log_prefix(state) <> "Recalculating due to new observation")
      send(self(), :recalculate)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:observation_disabled, obj_name}, %State{name: my_name} = state) do
    if obj_name == my_name do
      Logger.debug(log_prefix(state) <> "Recalculating due to observation being disabled")
      send(self(), :recalculate)
    end

    {:noreply, state}
  end

  defp with_cache(observations, cache) do
    observations
    |> Enum.map(&{&1, Map.get(cache, &1)})
  end

  defp build_solution([]), do: :unknown

  defp build_solution([_ | _] = geoms) do
    geoms
    |> Enum.reject(fn g -> g == :not_applicable end)
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

  defp describe_solution(:unknown, cache) do
    cache
    |> Map.values()
    |> Enum.filter(&(&1.solution == :unknown))
    |> Enum.map(fn entry -> entry.origin |> origin_name() end)
    |> then(fn
      [] -> ["Waiting for position data."]
      deps -> ["Waiting on position data for ", comma_list(deps), "."]
    end)
  end

  # Unless there's a bug, this should be a very temporary condition.
  defp describe_solution(:pending, _), do: :silent

  defp describe_solution(:disjoint, _) do
    ["Geometry is impossible!  All positions have been ruled out."]
  end

  defp describe_solution(%Geo.MultiPolygon{} = multi, _) do
    [
      "Multiple possible locations:",
      multi
      |> GeoEngine.split_multipolygon()
      |> Enum.with_index(1)
      |> Enum.map(fn {poly, index} ->
        [
          describe_shape(poly) |> :string.titlecase(),
          ".",
          "\n",
          describe_targeting(poly)
        ]
        |> indent(4)
        |> then(fn iodata -> ["\nLocation #{index}:\n" | iodata] end)
      end)
    ]
  end

  defp describe_solution(geometry, _) when is_geometry(geometry) do
    ["Location ", describe_shape(geometry), ".\n", describe_targeting(geometry)]
  end

  defp format_solution(iodata, title) do
    blank_prefix = String.duplicate(" ", String.length(title) + 2)

    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map(fn
      {line, 0} -> [title, ": ", line]
      {line, _} -> [blank_prefix, line]
    end)
    |> Enum.intersperse("\n")
  end

  defp describe_targeting(geometry) do
    {radius, _aimpoint} = GeoEngine.min_bounding_circle(geometry)
    uncertainty = ["Uncertainty radius is ", format_metres(radius)]

    case Ammo.Types.auto_suggest() |> Enum.find(fn ammo -> radius <= ammo.blast_radius end) do
      nil ->
        [uncertainty, "."]

      %Ammo{name: name, blast_radius: blast} ->
        percent = ceil(100 * radius / blast)
        [uncertainty, " (#{percent}% of an #{name} shell)."]
    end
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
  defp count_cells(n) when n > 20, do: "#{n}"

  def object_title(:ownship), do: "Iron Nest"
  def object_title(name), do: :string.titlecase(name)

  defp origin_name(:ownship), do: "Iron Nest"
  defp origin_name(name), do: name

  defp describe_shape(shape) do
    ints_by_sector = GeoEngine.count_grid_intersections_by_sector(shape)
    sectors = Enum.count(ints_by_sector)
    total_subs = ints_by_sector |> Enum.sum_by(fn {_, count} -> count end)

    cond do
      total_subs == 1 ->
        [sub] = GeoEngine.grid_intersections(shape)
        ["is in ", sub.name]

      total_subs <= 5 ->
        subs =
          GeoEngine.grid_intersections(shape)
          |> Enum.sort_by(&{&1.global_x, &1.global_y})
          |> Enum.map(& &1.name)

        ["is in one of ", comma_list(subs, "or")]

      sectors > 3 ->
        block = GeoEngine.centroid_grid_intersection(shape)
        [sector_name | _] = block.name |> String.split()
        "spans #{sectors} sectors around #{sector_name}"

      sectors > 1 ->
        by_sec =
          ints_by_sector
          |> Enum.map(fn {name, count} ->
            [count_cells(count), " in ", name]
          end)

        [
          "spans #{total_subs} grid squares",
          case GeoEngine.centroid_grid_intersection(shape) do
            %Grid.Block{name: n} -> " around #{n}"
            nil -> ""
          end,
          " --\n    ",
          comma_list(by_sec) |> :string.titlecase()
        ]

      total_subs == 100 ->
        [{name, _}] = ints_by_sector
        "is somewhere in sector #{name}"

      total_subs > 1 ->
        [{name, _}] = ints_by_sector

        [
          "is in one of #{total_subs} grid squares in sector ",
          name,
          case GeoEngine.centroid_grid_intersection(shape) do
            %Grid.Block{name: n} -> ", centred around #{n}"
            nil -> ""
          end
        ]
    end
  end

  defp format_metres(m) when m < 1000, do: "#{ceil(m)} metres"
  defp format_metres(m) when m >= 1000, do: "#{Float.ceil(m / 1000, 1)} kilometres"

  defp different_keys?(map1, map2) do
    keys1 = Map.keys(map1) |> Enum.sort()
    keys2 = Map.keys(map2) |> Enum.sort()
    keys1 != keys2
  end

  defp indent(iodata, count) do
    spaces = String.duplicate(" ", count)

    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.map(fn line -> [spaces, line] end)
    |> Enum.intersperse("\n")
  end
end
