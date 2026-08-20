defmodule Boom.Command.Aim do
  defmodule Parser do
    import NimbleParsec
    import Boom.CommandParser.ObjectName
    import Boom.CommandParser.Time
    alias Boom.CommandParser.ParseError

    def names, do: ["aim", "fire"]
    def usage(cmd), do: "#{cmd} [ammo...] at <target> [with <1..6> charges]"

    ammo = utf8_string([?A..?Z, ?a..?z], min: 1)

    ammo_list =
      ammo
      |> repeat(
        ignore(optional(string(" ")))
        |> ignore(utf8_char([?,, ?/, ?+]))
        |> ignore(optional(string(" ")))
        |> concat(ammo)
      )
      |> reduce({__MODULE__, :to_ammos, []})
      |> unwrap_and_tag(:ammos)

    min_charges =
      ignore(string(" with "))
      |> utf8_char([?1..?6])
      |> reduce({__MODULE__, :to_charges, []})
      |> optional(ignore(string(" charges")))
      |> unwrap_and_tag(:min_charges)

    movement =
      ignore(
        choice([
          string(" at "),
          string(" @") |> optional(string(" "))
        ])
      )
      |> time(:time)

    defparsec(
      :parse_args,
      choice([
        ignore(string("at ")),
        ammo_list |> ignore(string(" at "))
      ])
      |> object_name_until(
        choice([
          string(" with "),
          string(" at "),
          string(" @")
        ]),
        :target
      )
      |> choice([
        min_charges |> concat(movement),
        movement |> concat(min_charges),
        min_charges,
        movement,
        empty()
      ])
      |> eos()
      |> reduce({Boom.Command.Aim, :new, []})
    )

    def to_charges([c]), do: c - ?0

    def to_ammos(names) do
      names
      |> Enum.map(fn name ->
        case Boom.Ammo.Types.fetch(name) do
          {:ok, ammo} -> ammo
          :error -> raise ParseError, message: "Unknown ammo: #{inspect(name)}"
        end
      end)
    end
  end

  import Boom.Guards
  import Ecto.Query, only: [from: 2]
  alias Boom.Command
  alias Boom.Ammo
  alias Boom.DB.GeoEngine
  alias Boom.DB.Repo
  alias __MODULE__.Movement

  # Try the closest 7 bearings:
  @try_bearing_range -3..3//1
  # Try the closest 19 elevations:
  @try_elevation_range -9..9

  def new(opts) do
    {target, opts} = Keyword.pop!(opts, :target)
    {min_charges, opts} = Keyword.pop(opts, :min_charges)
    {ammos, opts} = Keyword.pop(opts, :ammos, Ammo.Types.auto_suggest())
    {time, opts} = Keyword.pop(opts, :time)
    unless Enum.empty?(opts), do: raise("Unknown options: #{inspect(opts)}")

    %Command{
      module: __MODULE__,
      args: [target, min_charges, ammos, time]
    }
  end

  def run(target, min_charges, [%Ammo{} | _] = ammos, time)
      when is_object_name(target) and (is_time(time) or is_nil(time)) do
    with {:ok, ownship_geom} <- get_solution(:ownship),
         {:ok, target_geom} <- get_solution(target, time) do
      %Geo.Point{coordinates: ownship_median} = GeoEngine.median(ownship_geom)
      %Geo.Point{coordinates: target_median} = GeoEngine.median(target_geom)

      ideal_bearing = ownship_median |> angle_to(target_median)
      ideal_distance = ownship_median |> distance_to(target_median)
      {powder_charges, ideal_elevation} = elevation_for(ideal_distance, min_charges)

      mid_bearing = Float.round(ideal_bearing, 1)
      mid_elevation = Float.round(ideal_elevation, 2)

      try_bearings = @try_bearing_range |> Enum.map(fn b -> {mid_bearing + b * 0.1, b} end)

      try_elevations =
        notch_span(@try_elevation_range, {powder_charges, mid_elevation}, min_charges)

      potentials = potential_solutions(try_bearings, try_elevations)
      target_area = GeoEngine.area(target_geom)

      ammos
      |> Enum.sort_by(& &1.blast_radius)
      |> try_ammo(ownship_geom, target_geom, potentials, target_area)
      |> Boom.output()
    else
      {:error, :no_solution, ^target} ->
        Boom.output("Cannot fire without a fix on the target.")

      {:error, :no_solution, :ownship} ->
        Boom.output("Cannot fire without a fix on our own location.")

      {:error, :no_movement} ->
        Boom.output("Target does not have any movement observations.")

      {:error, :moved_off_map} ->
        Boom.output("Target has moved off the map by #{time}.")
    end
  end

  defp try_ammo([ammo | rest], ownship_geom, target_geom, potentials, target_area) do
    {best_id, area} = best_solution(potentials, ownship_geom, target_geom, ammo)
    best = potentials |> Enum.find(&(&1.id == best_id))
    area_ratio = area / target_area

    {charges, elevation} = best.elevation
    distance = shot_distance(best.elevation)

    output =
      [
        "Using #{ammo.name} with",
        [
          "  charges = ",
          format_charges(charges) |> highlight(),
          " powder charge",
          if(charges == 1, do: "", else: "s")
        ],
        ["  bearing = ", format_bearing(best.bearing) |> highlight()],
        ["  elevation = ", format_elevation(elevation) |> highlight()],
        ["  distance = ", format_metres(distance)],
        ["has a hit probability of ", format_percent(area_ratio), "."]
      ]
      |> Enum.intersperse("\n")

    if area_ratio >= 0.999 || rest == [] do
      output
    else
      [output, "\n\n" | try_ammo(rest, ownship_geom, target_geom, potentials, target_area)]
    end
  end

  defp get_solution(object, time \\ nil)

  defp get_solution(object, nil) do
    case Boom.ObjectRegistry.solution(object) do
      g when is_geometry(g) -> {:ok, g}
      err when is_solution_error(err) -> {:error, :no_solution, object}
    end
  end

  defp get_solution(object, time) do
    with {:ok, from_geom} <- get_solution(object, nil),
         {:ok, to_geom} <- Movement.future_geometry(object, time, from_geom) do
      from_coord = GeoEngine.centroid(from_geom)
      to_coord = GeoEngine.centroid(to_geom)
      from_block = GeoEngine.centroid_grid_intersection(from_coord)
      to_block = GeoEngine.centroid_grid_intersection(to_coord)
      distance = from_coord.coordinates |> distance_to(to_coord.coordinates)

      Boom.output([
        "... ",
        Boom.Object.object_title(object),
        " moves ",
        format_metres(distance),
        if from_block == to_block do
          [" within ", from_block.name]
        else
          [" from ", from_block.name, " to ", to_block.name]
        end,
        " ..."
      ])

      {:ok, to_geom}
    end
  end

  defp distance_to({x1, y1}, {x2, y2}), do: :math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)

  defp angle_to({x1, y1}, {x2, y2}) do
    dx = x2 - x1
    dy = y2 - y1

    # atan2 normally takes (Y, X), but we deliberately swap it here.
    # This makes it return clockwise radians starting from north,
    # rather than counterclockwise radians starting from east.
    radians = :math.atan2(dx, dy)
    degrees = radians * 180.0 / :math.pi()
    if degrees < 0, do: degrees + 360, else: degrees
  end

  # elevation = distance_km * 12 / powder_charges
  # max elevation of 60°
  # which gives us a max distance of 30km
  defp elevation_for(distance, min_charges) when distance < 30000.0 do
    elevation = distance / 1000 * 12
    powder_charges = min_charges || elevation |> ceil() |> div(60) |> Kernel.+(1)
    {powder_charges, elevation / powder_charges}
  end

  # elevation = distance_km * 12 / powder_charges
  # 1 / distance_km = 12 / powder_charges / elevation
  # distance_km = 1 / (12 / powder_charges / elevation)
  # distance_m = 1000 / (12 / powder_charges / elevation)
  defp shot_distance({charges, elevation}), do: 1000 / (12 / charges / elevation)

  defp shot_offset(bearing, elevation) do
    distance = shot_distance(elevation)
    radians = bearing * :math.pi() / 180.0
    x = distance * :math.sin(radians)
    y = distance * :math.cos(radians)
    {x, y}
  end

  defp notch_span(min..max//span, {_, _} = pow_elev, min_charges) do
    lower = -1..min//-span |> repeatedly(&notch_down/2, pow_elev, min_charges)
    upper = 1..max//span |> repeatedly(&notch_up/2, pow_elev, min_charges)

    [
      lower |> Enum.with_index(1) |> Enum.map(fn {v, i} -> {v, -i} end),
      [{pow_elev, 0}],
      upper |> Enum.with_index(1)
    ]
    |> Enum.reduce(&Kernel.++/2)
  end

  defp repeatedly([], _, _, _), do: []

  defp repeatedly([_ | rest], fun, {_, _} = value, min) do
    next_value = fun.(value, min)
    [next_value | repeatedly(rest, fun, next_value, min)]
  end

  defp repeatedly(_.._//_ = range, fun, {_, _} = value, min),
    do: range |> Enum.to_list() |> repeatedly(fun, value, min)

  defp notch_up({charges, elevation}, _) do
    case elevation + 0.01 do
      e when e <= 60 -> {charges, e}
      e when e > 60 -> {charges + 1, e * charges / (charges + 1)}
    end
  end

  defp notch_down({1, elevation}, _), do: {1, elevation - 0.01}

  # At min_charges already:
  defp notch_down({charges, elevation}, charges), do: {charges, elevation - 0.01}

  defp notch_down({charges, elevation}, _) do
    new_elevation = elevation - 0.01

    case new_elevation * charges / (charges - 1) do
      e when e <= 60 -> {charges - 1, e}
      e when e > 60 -> {charges, new_elevation}
    end
  end

  @area_covered_sql """
  SELECT
    id,
    ideal_delta,
    target_area_covered(?::geometry, ?::geometry, x, y, ?::double precision) AS area
  FROM unnest(
    ?::integer[],
    ?::integer[],
    ?::double precision[],
    ?::double precision[]
  ) AS inputs(id, ideal_delta, x, y)
  """

  defmodule Potential do
    @enforce_keys [:id, :bearing, :elevation, :offset, :ideal_delta]
    defstruct(@enforce_keys)
  end

  defp potential_solutions(try_bearings, try_elevations) do
    try_bearings
    |> Enum.flat_map(fn {bearing, bearing_delta} ->
      try_elevations
      |> Enum.map(fn {{_, _} = elevation, elevation_delta} ->
        {
          bearing,
          elevation,
          abs(bearing_delta) + abs(elevation_delta)
        }
      end)
    end)
    |> Enum.with_index()
    |> Enum.map(fn {{bearing, elevation, ideal_delta}, index} ->
      %Potential{
        id: index,
        bearing: bearing,
        elevation: elevation,
        offset: shot_offset(bearing, elevation),
        ideal_delta: ideal_delta
      }
    end)
  end

  defp best_solution(potentials, ownship_geom, target_geom, %Ammo{blast_radius: blast}) do
    ids = potentials |> Enum.map(& &1.id)
    ideal_deltas = potentials |> Enum.map(& &1.ideal_delta)
    {x_offsets, y_offsets} = potentials |> Enum.map(& &1.offset) |> Enum.unzip()

    from(
      q in fragment(
        @area_covered_sql,
        ^ownship_geom,
        ^target_geom,
        ^blast,
        ^ids,
        ^ideal_deltas,
        ^x_offsets,
        ^y_offsets
      ),
      select: [fragment("id"), fragment("area")],
      order_by: [desc: fragment("area"), asc: fragment("ideal_delta")],
      limit: 1
    )
    |> Repo.one()
    |> then(fn [best_id, area] -> {best_id, area} end)
  end

  defp format_charges(1), do: "one"
  defp format_charges(2), do: "two"
  defp format_charges(3), do: "three"
  defp format_charges(4), do: "four"
  defp format_charges(5), do: "five"
  defp format_charges(6), do: "six"
  defp format_bearing(degrees), do: [format_float(degrees, 1), "°"]
  defp format_elevation(degrees), do: [format_float(degrees, 2), "°"]
  defp format_percent(1.0), do: "100%"
  defp format_percent(ratio), do: [format_float(ratio * 100, 1), "%"]
  defp format_metres(m) when m >= 1000, do: [format_float(m / 1000, 2), " km"]
  defp format_metres(m) when m < 1000, do: [round(m) |> to_string(), " m"]

  defp format_float(float, decimals), do: :erlang.float_to_binary(float, decimals: decimals)
  defp highlight(iodata), do: [IO.ANSI.light_green(), iodata, IO.ANSI.reset()]
end
