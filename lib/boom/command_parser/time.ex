defmodule Boom.CommandParser.Time do
  import NimbleParsec

  def time(combinator \\ empty(), tag_as) do
    combinator
    |> concat(
      integer(min: 1, max: 2)
      |> ignore(string(":"))
      |> integer(min: 1, max: 2)
      |> ignore(string(":"))
      |> integer(min: 1, max: 2)
      |> reduce({__MODULE__, :to_time, []})
      |> unwrap_and_tag(tag_as)
    )
  end

  def to_time([h, m, s]), do: Time.new!(h, m, s)
end
