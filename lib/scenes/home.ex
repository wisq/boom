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

  alias Scenic.{Scene, Graph, Primitive}
  alias Scenic.Primitives, as: P

  @major_columns ?A..?T |> Enum.map(&<<&1>>)
  @major_rows 1..10 |> Enum.reverse()
  @minor_subdivisions 10

  @major_grid_width Enum.count(@major_columns)
  @major_grid_height Enum.count(@major_rows)
  @minor_grid_width @major_grid_width * @minor_subdivisions
  @minor_grid_height @major_grid_height * @minor_subdivisions

  @major_line_colour :white
  @minor_line_colour {255, 255, 255, 64}
  @sector_label_colour {255, 255, 255, 192}

  @coords_tooltip_offset {5, 5}
  @min_padding 10
  @scroll_delay 20

  @impl true
  def init(%Scene{} = scene, _param, _opts) do
    size = scene.viewport.size
    zoom = minimum_zoom_level(size)

    state = %State{
      min_zoom: zoom,
      viewport_size: size
    }

    :ok = request_input(scene, [:cursor_pos, :cursor_button, :cursor_scroll, :viewport])
    {:ok, scene |> assign(:state, state) |> queue_render()}
  end

  @impl true
  def handle_input(
        {:viewport, {:reshape, {_, _} = size}},
        _context,
        %Scene{assigns: %{state: %State{} = state}} = scene
      ) do
    min_zoom = minimum_zoom_level(size)

    cur_zoom =
      case state.current_zoom do
        nil -> nil
        zoom when is_integer(zoom) -> max(state.current_zoom, min_zoom)
      end

    state = %State{
      state
      | viewport_size: size,
        min_zoom: min_zoom,
        current_zoom: cur_zoom
    }

    Boom.save_viewport_size(size)

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
        n when n > 0 -> old_zoom - 1
        n when n < 0 -> old_zoom + 1
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

  defp rebuild_graph(%State{} = state) do
    zoom = state.current_zoom || state.min_zoom
    width = @minor_grid_width * zoom + 1
    height = @minor_grid_height * zoom + 1

    graph =
      Graph.build(font: :roboto, font_size: 20)
      |> P.group(
        fn g ->
          g
          |> draw_minor_lines(zoom, width, height)
          |> draw_major_lines(zoom, width, height)
          |> label_sectors(zoom)
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

  defp draw_minor_lines(graph, zoom, _, _) when zoom < 8, do: graph

  defp draw_minor_lines(graph, zoom, width, height) do
    graph =
      Enum.reduce(0..@minor_grid_width, graph, fn column, acc ->
        x = column * zoom
        P.line(acc, {{x, 0}, {x, height}}, stroke: {1, @minor_line_colour})
      end)

    Enum.reduce(0..@minor_grid_height, graph, fn row, acc ->
      y = row * zoom
      P.line(acc, {{0, y}, {width, y}}, stroke: {1, @minor_line_colour})
    end)
  end

  defp draw_major_lines(graph, zoom, width, height) do
    graph =
      Enum.reduce(0..@major_grid_width, graph, fn column, acc ->
        x = column * zoom * @minor_subdivisions
        P.line(acc, {{x, 0}, {x, height}}, stroke: {1, @major_line_colour})
      end)

    Enum.reduce(0..@major_grid_height, graph, fn row, acc ->
      y = row * zoom * @minor_subdivisions
      P.line(acc, {{0, y}, {width, y}}, stroke: {1, @major_line_colour})
    end)
  end

  defp label_sectors(graph, zoom) do
    @major_columns
    |> Enum.with_index()
    |> Enum.flat_map(fn {column, x} ->
      @major_rows
      |> Enum.with_index()
      |> Enum.map(fn {row, y} ->
        {"#{column}#{row}", {x, y}}
      end)
    end)
    |> Enum.reduce(graph, fn {label, {column, row}}, acc ->
      x = column * zoom * @minor_subdivisions
      y = row * zoom * @minor_subdivisions

      P.text(acc, label, translate: {x + 2, y + 22}, fill: @sector_label_colour)
    end)
  end

  defp transform_map(%Graph{} = graph, {_, _} = offset) do
    Graph.modify(graph, :map, &Primitive.put_transform(&1, :translate, offset))
  end

  @coords_range_x 0..(@minor_grid_width - 1)
  @coords_range_y 0..(@minor_grid_height - 1)

  defp update_coords(%Graph{} = graph, {cursor_x, cursor_y} = cursor, {offset_x, offset_y}, zoom) do
    grid_x = (cursor_x - offset_x) |> floor() |> div(zoom)
    grid_y = (cursor_y - offset_y) |> floor() |> div(zoom)

    if grid_x in @coords_range_x && grid_y in @coords_range_y do
      {major_x, minor_x} = grid_x |> div_rem(@minor_subdivisions)
      {major_y, minor_y} = grid_y |> div_rem(@minor_subdivisions)

      major_column = @major_columns |> Enum.at(major_x)
      major_row = @major_rows |> Enum.at(major_y)
      minor_column = minor_x
      minor_row = @minor_subdivisions - 1 - minor_y

      coords = "#{major_column}#{major_row}  #{minor_column}:#{minor_row}"

      graph
      |> Graph.modify(:coords_text, &P.text(&1, coords))
      |> Graph.modify(
        :coords,
        &Primitive.put_transform(&1, :translate, cursor |> coords_add(@coords_tooltip_offset))
      )
    else
      graph
    end
  end

  defp div_rem(x, y), do: {div(x, y), rem(x, y)}

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
    # The +1 accounts for the final grid line in each direction.
    by_width = div(width - 1 - @min_padding, @minor_grid_width)
    by_height = div(height - 1 - @min_padding, @minor_grid_height)
    min(by_width, by_height)
  end
end
