defmodule Boom.Command.Observe do
  defmodule Parser do
    import NimbleParsec
    import Boom.CommandParser.ObjectName
    import Boom.CommandParser.Time
    import Boom.CommandParser.Compass
    import Boom.CommandParser.Helpers

    def usage, do: "<target> is at <grid>  /  <target> is <observations...> from <origin>"

    block =
      utf8_char([?A..?T, ?a..?t])
      |> choice([
        string("10"),
        utf8_char([?1..?9])
      ])
      |> optional(
        string(" ")
        |> utf8_char([?0..?9])
        |> string(":")
        |> utf8_char([?0..?9])
      )
      |> reduce({__MODULE__, :to_block, []})
      |> unwrap_and_tag(:origin)
      |> label("block name")

    float_with_error =
      integer(min: 1)
      |> optional(
        string(".")
        |> utf8_string([?0..?9], min: 1)
      )
      |> reduce({__MODULE__, :to_float_with_error, []})

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
      float_with_error
      |> optional(range_suffix)
      |> reduce({__MODULE__, :to_range, []})
      |> unwrap_and_tag(:range)

    range_with_suffix =
      float_with_error
      |> concat(range_suffix)
      |> reduce({__MODULE__, :to_range, []})
      |> unwrap_and_tag(:range)

    bearing_suffix =
      ignore(
        choice([
          string("°"),
          string(" degree") |> optional(string("s")),
          optional(string(" ")) |> choice([string("deg"), string("d")])
        ])
      )

    bearing =
      float_with_error
      |> optional(bearing_suffix)
      |> unwrap_and_tag(:bearing)

    bearing_with_suffix =
      float_with_error
      |> concat(bearing_suffix)
      |> unwrap_and_tag(:bearing)

    speed =
      float_with_error
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
      object_name_until(" is ", :target)
      |> ignore(string(" is "))
      |> choice([
        # x is at a1 2:3
        ignore(
          choice([
            string("at "),
            string("in ")
          ])
        )
        |> concat(block)
        |> post_traverse(:handle_at)
        |> label("at <block>")
        |> optional(ignore(string(" ")) |> concat(moving)),

        # x is <ref> from <obj/block>
        times(
          choice([
            ignore(string("range ")) |> concat(range),
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
          block,
          object_name(:origin)
        ]),

        # x is moving <dir> at <speed> from <time>
        moving
      ])
      |> label(~s{"at <block>" OR "<constraints> from <target>"})
      |> eos()
      |> reduce({Boom.Command.Observe, :new, []})
    )

    def to_block(parts) do
      {:ok, block} = recombine(parts) |> Boom.Grid.block_by_name()
      block
    end

    def to_float_with_error([int]), do: {int + 0.0, 0.5}

    def to_float_with_error([int, ".", dec]) do
      len = String.length(dec)
      {String.to_float("#{int}.#{dec}"), 0.5 * 10 ** -len}
    end

    def to_range([{value, error}, units]), do: {value * units, error * units}
    def to_range([{value, error}]), do: {value * 1000, error * 1000}

    defp handle_at(rest, [origin: block], ctx, _, _) do
      {rest, [origin: block, at: true], ctx}
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
