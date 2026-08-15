defmodule Boom.Scene.Home do
  defmodule State do
    @enforce_keys [:min_zoom, :viewport_size]

    defstruct(
      # Minimum zoom based on window size.
      # Zoom = number of pixels per minor cell.
      min_zoom: nil,
      # Current user-selected zoom level.
      # If nil, the user has not zoomed yet; default to min_zoom.
      current_zoom: nil,
      # Last zoomlevel we rendered at.
      # If this hasn't changed, we don't need to re-render.
      last_zoom: nil,
      # Size of the viewport and the map.  Used for centering the map when zoomed out.
      viewport_size: nil,
      map_size: {0, 0},
      # Offset of the map, in pixels distance from origin.
      # Will almost certainly be immediately updated by recentering on launch.
      offset: {0, 0},
      # Mouse cursor position.  Used to render the coordinate tooltip.
      cursor: {0, 0},
      # Are we currently drag-panning the map around?
      panning: false,
      # Render and zoom events are ignored while an event is already pending.
      render_pending: false,
      zoom_pending: false,
      # The cached graph, so that we only need to rebuild it on zoom.
      graph: nil
    )
  end

  use Scenic.Scene
  require Logger
  import Boom.Guards

  alias Scenic.{Scene, Graph, Primitive}
  alias Scenic.Primitives, as: P
  alias Boom.Grid
  alias Boom.Grid.Block

  @major_line_stroke {1, :white}
  @minor_line_stroke {1, {255, 255, 255, 64}}
  @sector_label_colour {255, 255, 255, 192}

  @coords_tooltip_offset {5, 5}

  @min_padding 10
  @scroll_delay 20
  @zoom_factor 1.05

  @impl true
  def init(%Scene{} = scene, _param, _opts) do
    size = scene.viewport.size
    zoom = minimum_zoom_level(size)

    build_lines()

    state = %State{
      min_zoom: zoom,
      viewport_size: size
    }

    :ok = request_input(scene, [:cursor_pos, :cursor_button, :cursor_scroll, :viewport])
    PubSub.subscribe(self(), :object_registry)
    {:ok, scene |> assign(:state, state) |> queue_render()}
  end

  @impl true
  def handle_input(
        {:viewport, {:reshape, {_, _} = new_size}},
        _context,
        %Scene{assigns: %{state: %State{viewport_size: old_size} = state}} = scene
      ) do
    min_zoom = minimum_zoom_level(new_size)

    cur_zoom =
      case state.current_zoom do
        nil -> nil
        zoom when is_integer(zoom) -> max(state.current_zoom, min_zoom)
      end

    state = %State{
      state
      | viewport_size: new_size,
        min_zoom: min_zoom,
        current_zoom: cur_zoom
    }

    if is_resize_significant?(old_size, new_size) do
      Boom.save_viewport_size(new_size)
    end

    {:noreply, scene |> assign(state: state) |> queue_render()}
  end

  def handle_input({:viewport, {:enter, _}}, _, scene), do: {:noreply, scene}
  def handle_input({:viewport, {:exit, _}}, _, scene), do: {:noreply, scene}

  @impl true
  def handle_input(
        {:cursor_button, {:btn_left, 1, _, {_, _} = coords}},
        _context,
        %Scene{assigns: %{state: %State{} = state}} = scene
      ) do
    state = %State{state | panning: coords}
    {:noreply, scene |> assign(:state, state)}
  end

  @impl true
  def handle_input(
        {:cursor_button, {:btn_left, 0, _, {_, _} = coords}},
        _context,
        %Scene{assigns: %{state: %State{} = state}} = scene
      ) do
    state = state |> apply_pan(coords)
    state = %State{state | panning: nil}
    {:noreply, scene |> assign(:state, state) |> queue_render()}
  end

  @impl true
  def handle_input(
        {:cursor_pos, coords},
        _context,
        %Scene{assigns: %{state: %State{} = state}} = scene
      ) do
    state = state |> apply_pan(coords)
    {:noreply, scene |> assign(:state, state) |> queue_render()}
  end

  @impl true
  def handle_input(
        {:cursor_scroll, _},
        _context,
        %Scene{assigns: %{state: %State{zoom_pending: true}}} = scene
      ),
      do: {:noreply, scene}

  @impl true
  def handle_input(
        {:cursor_scroll, {{_, scroll_by}, coords}},
        _context,
        %Scene{assigns: %{state: %State{} = state}} = scene
      ) do
    old_zoom = state.current_zoom || state.min_zoom

    new_zoom =
      case scroll_by do
        n when n > 0 -> floor(old_zoom / @zoom_factor)
        n when n < 0 -> ceil(old_zoom * @zoom_factor)
        _ -> old_zoom
      end

    Process.send_after(self(), {:zoom, new_zoom, coords}, @scroll_delay)
    state = %State{state | zoom_pending: true}
    {:noreply, scene |> assign(:state, state)}
  end

  @impl true
  def handle_input(input, _context, scene) do
    Logger.debug("Unhandled input: #{inspect(input)}")
    {:noreply, scene}
  end

  @impl true
  def handle_info(:render, %Scene{assigns: %{state: %State{} = state}} = scene) do
    zoom = state.current_zoom || state.min_zoom

    state =
      if state.last_zoom == zoom do
        state
      else
        %State{state | last_zoom: zoom}
        |> rebuild_graph()
      end
      |> recentre_map(state.viewport_size)

    graph =
      state.graph
      |> transform_map(state.offset)
      |> update_coords(state.cursor, state.offset, zoom)

    scene = push_graph(scene, graph)
    state = %State{state | render_pending: false}
    {:noreply, scene |> assign(:state, state)}
  end

  @impl true
  def handle_info(
        {:zoom, new_zoom, {mouse_x, mouse_y}},
        %Scene{assigns: %{state: %State{} = state}} = scene
      ) do
    old_zoom = state.current_zoom || state.min_zoom
    new_zoom = new_zoom |> max(state.min_zoom)

    {old_offset_x, old_offset_y} = state.offset
    old_world_x = (mouse_x - old_offset_x) / old_zoom
    old_world_y = (mouse_y - old_offset_y) / old_zoom

    new_offset_x = mouse_x - old_world_x * new_zoom
    new_offset_y = mouse_y - old_world_y * new_zoom
    new_offset = {new_offset_x, new_offset_y}

    state = %State{state | offset: new_offset, current_zoom: new_zoom, zoom_pending: false}
    {:noreply, scene |> assign(:state, state) |> queue_render()}
  end

  @impl true
  def handle_info({:object_updated, _}, %Scene{assigns: %{state: %State{} = state}} = scene) do
    # Force a re-render.
    state = %State{state | last_zoom: nil}
    {:noreply, scene |> assign(:state, state) |> queue_render()}
  end

  defp rebuild_graph(%State{} = state) do
    {grid_width, grid_height} = Grid.grid_size()
    zoom = state.current_zoom || state.min_zoom
    width = grid_width * zoom + 1
    height = grid_height * zoom + 1

    graph =
      Graph.build(font: :roboto, font_size: 20)
      |> P.group(
        fn g ->
          g
          |> draw_lines(:minor, minor_grid_lines(), @minor_line_stroke, zoom, width, height)
          |> draw_lines(:major, major_grid_lines(), @major_line_stroke, zoom, width, height)
          |> label_sectors(zoom)
          |> draw_object_geometries(zoom)
        end,
        id: :map
      )
      |> P.group(
        fn g ->
          g
          |> P.rect({80, 30}, fill: :black, stroke: {2, :white})
          |> P.text("", translate: {5, 22}, id: :coords_text)
        end,
        id: :coords,
        # Deliberately offscreen by default:
        translate: {-1000, -1000}
      )

    %State{state | graph: graph, map_size: {width, height}}
  end

  defp draw_lines(graph, :minor, _, _, zoom, _, _) when zoom < 8, do: graph

  defp draw_lines(graph, _type, lines, stroke, zoom, width, height) do
    lines
    |> Enum.map(fn
      {:vertical, column} ->
        x = column * zoom
        {{x, 0}, {x, height}}

      {:horizontal, row} ->
        y = row * zoom
        {{0, y}, {width, y}}
    end)
    |> Enum.reduce(graph, fn coords, gr ->
      P.line(gr, coords, stroke: stroke)
    end)
  end

  defp label_sectors(graph, zoom) do
    Grid.sectors()
    |> Enum.reduce(graph, fn %Block{name: name, extents: {gx.._//_, gy.._//_}}, gr ->
      x = gx * zoom
      y = gy * zoom

      P.text(gr, name, translate: {x + 2, y + 22}, fill: @sector_label_colour)
    end)
  end

  defp draw_object_geometries(graph, zoom) do
    Boom.ObjectRegistry.all_solutions()
    |> Enum.reduce(graph, fn {name, geometry}, gr ->
      colour = pick_colour(name)
      draw_polygon(gr, geometry, zoom, fill: colour, stroke: {2, brighter(colour)})
    end)
  end

  defp transform_map(%Graph{} = graph, {_, _} = offset) do
    Graph.modify(graph, :map, &Primitive.put_transform(&1, :translate, offset))
  end

  defp update_coords(%Graph{} = graph, {cursor_x, cursor_y} = cursor, {offset_x, offset_y}, zoom) do
    grid_x = ((cursor_x - offset_x) / zoom) |> floor()
    grid_y = ((cursor_y - offset_y) / zoom) |> floor()

    case Grid.subdivision_at(grid_x, grid_y) do
      {:ok, block} ->
        graph
        |> Graph.modify(:coords_text, &P.text(&1, block.name))
        |> Graph.modify(
          :coords,
          &Primitive.put_transform(&1, :translate, cursor |> coords_add(@coords_tooltip_offset))
        )

      :error ->
        graph
    end
  end

  defp recentre_map(
         %State{map_size: map_size, offset: old_offset} = state,
         viewport_size
       ) do
    new_offset =
      [map_size, viewport_size, old_offset]
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.zip_with(fn
        [ms, vs, _offset] when vs >= ms -> (vs - ms) |> div(2)
        [_ms, _vs, offset] -> offset
      end)
      |> List.to_tuple()

    %State{state | offset: new_offset}
  end

  defp apply_pan(%State{cursor: old_coords, offset: old_offset} = state, new_coords) do
    new_offset =
      if state.panning do
        delta = coords_subtract(new_coords, old_coords)
        coords_add(old_offset, delta)
      else
        old_offset
      end

    %State{state | cursor: new_coords, offset: new_offset}
  end

  defp coords_add({ax, ay}, {bx, by}), do: {ax + bx, ay + by}
  defp coords_subtract({ax, ay}, {bx, by}), do: {ax - bx, ay - by}

  defp queue_render(%Scene{assigns: %{state: %State{render_pending: true}}} = scene), do: scene

  defp queue_render(%Scene{assigns: %{state: %State{render_pending: false} = state}} = scene) do
    send(self(), :render)
    scene |> assign(:state, %State{state | render_pending: true})
  end

  # Determine the lowest zoomlevel (pixels per minor grid line)
  # where the entire grid (plus @min_padding) fits within the window.
  defp minimum_zoom_level({width, height}) do
    {grid_width, grid_height} = Grid.grid_size()
    # The +1 accounts for the final grid line in each direction.
    by_width = div(width - 1 - @min_padding, grid_width)
    by_height = div(height - 1 - @min_padding, grid_height)
    min(by_width, by_height)
  end

  # Some window managers tend to do a bit of minor futzing with size at
  # startup. To avoid saving all these (and the window size creeping
  # bigger/smaller across multiple startups), skip saving minor changes.
  defp is_resize_significant?({x1, y1}, {x2, y2}) do
    abs(x1 - x2) >= 5 || abs(y1 - y2) >= 5
  end

  @hue_range {0.0, 360.0}
  @saturation_range {30.0, 70.0}
  @lightness_range {30.0, 70.0}
  @maxint32 2 ** 32

  def pick_colour(:ownship), do: {:color_hsl, {0, 70.0, 70.0}}

  def pick_colour(name) do
    <<hue_seed::32, sat_seed::32, light_seed::32, _::binary>> = :crypto.hash(:md5, name)

    hue = pick_in_range(@hue_range, hue_seed)
    sat = pick_in_range(@saturation_range, sat_seed)
    light = pick_in_range(@lightness_range, light_seed)

    {:color_hsl, {hue, sat, light}}
  end

  defp pick_in_range({min, max}, byte) when byte in 0..@maxint32 do
    min + byte / @maxint32 * (max - min)
  end

  defp brighter({:color_hsl, {hue, _, _}}), do: {:color_hsl, {hue, 100.0, 90.0}}

  defp draw_polygon(graph, err, _, _) when is_solution_error(err), do: graph

  defp draw_polygon(graph, geometry, zoom, opts) when is_geometry(geometry) do
    geometry
    |> to_polygons()
    |> Enum.flat_map(&geo_inner_outer_coords/1)
    |> Enum.reduce(graph, fn
      {:outer, geom}, gr ->
        P.path(gr, coords_to_path(geom, zoom), opts)

      {:inner, geom}, gr ->
        P.path(gr, coords_to_path(geom, zoom), Keyword.put(opts, :fill, :black))
    end)
  end

  defp to_polygons(%Geo.MultiPolygon{} = m), do: Boom.DB.GeoEngine.split_multipolygon(m)
  defp to_polygons(%Geo.Polygon{} = p), do: [p]
  defp to_polygons(%_{} = other), do: [Boom.DB.GeoEngine.buffer(other, 1)]

  defp geo_inner_outer_coords(%Geo.Polygon{coordinates: [outer, inner]}),
    do: [{:outer, outer}, {:inner, inner}]

  defp geo_inner_outer_coords(%Geo.Polygon{coordinates: [outer]}), do: [{:outer, outer}]

  defp coords_to_path([coord | rest], zoom) do
    {x, y} = Block.geo_coord_to_grid(coord)

    [
      :begin,
      {:move_to, x * zoom, y * zoom}
      | coords_to_path_rest(rest, zoom)
    ]
  end

  defp coords_to_path_rest([{_, _}], _), do: [:close_path]

  defp coords_to_path_rest([coord | rest], zoom) do
    {x, y} = Block.geo_coord_to_grid(coord)

    [
      {:line_to, x * zoom, y * zoom}
      | coords_to_path_rest(rest, zoom)
    ]
  end

  @major_grid_lines __MODULE__.MajorGridLines
  @minor_grid_lines __MODULE__.MinorGridLines

  defp major_grid_lines, do: :persistent_term.get(@major_grid_lines)
  defp minor_grid_lines, do: :persistent_term.get(@minor_grid_lines)

  defp build_lines do
    :persistent_term.put(@major_grid_lines, Grid.sectors() |> lines_from_blocks())
    :persistent_term.put(@minor_grid_lines, Grid.subdivisions() |> lines_from_blocks())
  end

  defp lines_from_blocks(blocks) do
    blocks
    |> Enum.flat_map(fn %Block{extents: {min_x..max_x//_, min_y..max_y//_}} ->
      [
        {:vertical, min_x},
        {:vertical, max_x + 1},
        {:horizontal, min_y},
        {:horizontal, max_y + 1}
      ]
    end)
    |> Enum.uniq()
  end
end
