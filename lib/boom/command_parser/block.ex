defmodule Boom.CommandParser.Block do
  import NimbleParsec
  import Boom.CommandParser.Helpers

  def block(combinator \\ empty(), tag_as) do
    combinator
    |> concat(
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
      |> unwrap_and_tag(tag_as)
      |> label("block name")
    )
  end

  def to_block(parts) do
    {:ok, block} = recombine(parts) |> Boom.Grid.block_by_name()
    block
  end
end
