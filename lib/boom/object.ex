defmodule Boom.Object do
  use GenServer
  require Logger

  alias Boom.ObjectRegistry
  alias Boom.Command
  alias Boom.CommandLog
  alias Boom.Grid
  alias Boom.GeoEngine
  import Boom.ObjectRegistry, only: [is_object_name: 1]

  defmodule State do
    @enforce_keys [:name]
    defstruct(
      name: nil,
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
      {:ok, %State{name: name}}
    end
  end

  @impl true
  def handle_info(:recalculate, %State{} = state) do
    entries =
      CommandLog.active_entries(state.name)
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

      version = state.version + 1

      ObjectRegistry.update(state.name, version, geometry)
      Logger.info(log_prefix(state) <> "Updated to version #{version}")
      {:noreply, %State{state | version: version}}
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
  def handle_info({:command_added, name}, %State{name: name} = state) do
    Logger.debug(log_prefix(state) <> "Recalculating due to added command")
    send(self(), :recalculate)
    {:noreply, state}
  end

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
end
