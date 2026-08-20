defmodule Boom.Command.Observe do
  defmodule Parser do
    import NimbleParsec
    import Boom.CommandParser.ObjectName
    import Boom.CommandParser.Block
    import Boom.CommandParser.Time
    import Boom.CommandParser.FloatWithError
    import Boom.CommandParser.Compass

    def usage, do: "<target> is at <grid>  /  <target> is <observations...> from <origin>"

    range_suffix =
      choice([
        ignore(string(" "))
        |> choice([
          string("kilometre") |> replace(1000),
          string("kilometer") |> replace(1000),
          string("metre") |> replace(1),
          string("meter") |> replace(1)
        ])
        |> optional(ignore(string("s"))),
        optional(ignore(string(" ")))
        |> choice([
          string("km") |> replace(1000),
          string("m") |> replace(1)
        ])
      ])

    range =
      float_with_error()
      |> optional(range_suffix)
      |> reduce({__MODULE__, :to_range, []})
      |> unwrap_and_tag(:range)

    range_with_suffix =
      float_with_error()
      |> concat(range_suffix)
      |> reduce({__MODULE__, :to_range, []})
      |> unwrap_and_tag(:range)

    bearing_suffix =
      ignore(
        choice([
          string("°"),
          string(" degree") |> optional(string("s")),
          optional(string(" "))
          |> choice([
            string("deg") |> optional(string("s")),
            string("d")
          ])
        ])
      )

    bearing =
      float_with_error()
      |> optional(bearing_suffix)
      |> unwrap_and_tag(:bearing)

    bearing_with_suffix =
      float_with_error()
      |> concat(bearing_suffix)
      |> unwrap_and_tag(:bearing)

    speed =
      float_with_error()
      |> ignore(
        choice([
          string(" knot") |> optional(string("s")),
          optional(string(" ")) |> string("kn"),
          empty()
        ])
      )
      |> unwrap_and_tag(:speed)

    moving =
      ignore(string("moving "))
      |> concat(bearing)
      |> ignore(string(" at "))
      |> concat(speed)
      |> ignore(
        choice([
          string(" since "),
          string(" @") |> optional(string(" "))
        ])
      )
      |> time(:time)
      |> reduce(:handle_moving)

    defparsec(
      :parse_observation,
      object_name_until(choice([string(" is "), string(" has ")]), :target)
      |> choice([
        # x is at <block>
        ignore(
          choice([
            string(" is at "),
            string(" is in ")
          ])
        )
        |> block(:origin)
        |> post_traverse(:handle_at)
        |> label("at <block>")
        |> optional(ignore(string(" ")) |> concat(moving)),

        # x is <ref> from <obj/block>
        ignore(string(" is "))
        |> times(
          choice([
            ignore(string("range ")) |> concat(range),
            ignore(string("distance ")) |> concat(range),
            ignore(string("bearing ")) |> concat(bearing),
            ignore(string("due ")) |> compass(:bearing),
            range_with_suffix,
            bearing_with_suffix,
            compass(:bearing)
          ])
          |> label(~s{"range <r>" OR "bearing <b>" OR "<r>km" OR "<b>°"})
          |> optional(ignore(string(",")))
          |> optional(ignore(string(" "))),
          min: 1
        )
        |> label("one or more constraints")
        |> ignore(
          choice([
            string("from "),
            string("of ")
          ])
        )
        |> choice([
          block(:origin),
          object_name(:origin)
        ]),

        # x has moved [to <block>]
        ignore(string(" has moved"))
        |> optional(
          ignore(string(" to "))
          |> block(:origin)
        )
        |> post_traverse(:handle_invalidate)
        |> label("has moved [to <block>]"),

        # x is moving <dir> at <speed> from <time>
        ignore(string(" is "))
        |> concat(moving)
      ])
      |> label(~s{"at <block>" OR "<constraints> from <target>"})
      |> eos()
      |> reduce({Boom.Command.Observe, :new, []})
    )

    def to_range([{value, error}, units]), do: {value * units, error * units}
    def to_range([{value, error}]), do: {value * 1000, error * 1000}

    defp handle_at(rest, [origin: block], ctx, _, _) do
      {rest, [origin: block, at: true], ctx}
    end

    defp handle_invalidate(rest, [origin: block], ctx, _, _) do
      {rest, [origin: block, at: true, invalidate: true], ctx}
    end

    defp handle_invalidate(rest, [], ctx, _, _) do
      {rest, [invalidate: true], ctx}
    end

    defp handle_moving(opts) do
      {:moving,
       {
         Keyword.fetch!(opts, :bearing),
         Keyword.fetch!(opts, :speed),
         Keyword.fetch!(opts, :time)
       }}
    end
  end

  alias Boom.Command
  alias Boom.Observation
  alias Boom.ObservationLog

  def new(opts) do
    {target, opts} = Keyword.pop!(opts, :target)
    {origin, opts} = Keyword.pop(opts, :origin)

    opts
    |> Enum.map(fn
      {:bearing, {bearing, error}} -> Observation.Bearing.new(bearing, error, origin, target)
      {:range, {range, error}} -> Observation.Range.new(range, error, origin, target)
      {:at, true} -> Observation.At.new(origin, target)
      {:invalidate, true} -> Observation.Invalidate.new(target)
      {:moving, {bearing, speed, time}} -> Observation.Moving.new(target, bearing, speed, time)
    end)
    |> then(fn observations ->
      %Command{
        module: __MODULE__,
        args: [observations]
      }
    end)
  end

  def run([%Observation{} | _] = obslist) do
    ObservationLog.add(obslist)
  end
end
