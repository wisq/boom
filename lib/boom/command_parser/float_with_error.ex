defmodule Boom.CommandParser.FloatWithError do
  import NimbleParsec

  def float_with_error(combinator \\ empty()) do
    combinator
    |> concat(
      integer(min: 1)
      |> optional(
        string(".")
        |> utf8_string([?0..?9], min: 1)
      )
      |> reduce({__MODULE__, :to_float_with_error, []})
    )
  end

  def to_float_with_error([int]), do: {int + 0.0, 0.5}

  def to_float_with_error([int, ".", dec]) do
    len = String.length(dec)
    {String.to_float("#{int}.#{dec}"), 0.5 * 10 ** -len}
  end
end
