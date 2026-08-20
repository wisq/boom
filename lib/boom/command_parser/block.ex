defmodule Boom.CommandParser.Block do
  import NimbleParsec
  import Boom.CommandParser.Helpers
  alias Boom.Grid

  @sector utf8_char([?A..?T, ?a..?t])
          |> choice([
            string("10"),
            utf8_char([?1..?9])
          ])

  @subdivision string(" ")
               |> utf8_char([?0..?9])
               |> string(":")
               |> utf8_char([?0..?9])

  @within_grid ignore(string(" "))
               |> utf8_char([?+, ?-])
               |> integer(2)
               |> utf8_char([?+, ?-])
               |> integer(2)

  def block(combinator \\ empty(), tag_as) do
    combinator
    |> concat(
      @sector
      |> optional(
        @subdivision
        |> optional(@within_grid)
      )
      |> reduce({__MODULE__, :to_block, []})
      |> unwrap_and_tag(tag_as)
      |> label("grid block")
    )
  end

  def to_block([_letter, _number] = sector) do
    {:ok, block} = recombine(sector) |> Grid.block_by_name()
    block
  end

  def to_block([letter, number, " ", x, ":", y | rest]) do
    {:ok, block} =
      [letter, number, " ", x, ":", y]
      |> recombine()
      |> Grid.block_by_name()

    case rest do
      [] ->
        block

      [xpm, x, ypm, y] ->
        x = to_subgrid(xpm, x)
        y = to_subgrid(ypm, y)
        block |> Grid.Block.within_block(x, y)
    end
  end

  defp to_subgrid(?+, n), do: n
  defp to_subgrid(?-, n), do: 100 - n
end
