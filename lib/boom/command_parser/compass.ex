defmodule Boom.CommandParser.Compass do
  import NimbleParsec

  north_word = string("north") |> replace(:north)
  south_word = string("south") |> replace(:south)
  east_word = string("east") |> replace(:east)
  west_word = string("west") |> replace(:west)

  cardinal_word = choice([north_word, south_word, east_word, west_word])
  ordinal_words = choice([north_word, south_word]) |> choice([east_word, west_word])

  subordinal_words =
    cardinal_word
    |> ignore(optional(string("-")))
    |> concat(ordinal_words)

  north_char = utf8_char([?N, ?n]) |> replace(:north)
  south_char = utf8_char([?S, ?s]) |> replace(:south)
  east_char = utf8_char([?E, ?e]) |> replace(:east)
  west_char = utf8_char([?W, ?w]) |> replace(:west)

  cardinal_char = choice([north_char, south_char, east_char, west_char])
  ordinal_chars = choice([north_char, south_char]) |> choice([east_char, west_char])
  subordinal_chars = cardinal_char |> concat(ordinal_chars)

  @parser choice([
            subordinal_words,
            subordinal_chars,
            ordinal_words,
            ordinal_chars,
            cardinal_word,
            cardinal_char
          ])
          |> reduce({__MODULE__, :to_compass_bearing, []})

  def compass(combinator \\ empty(), tag_as) do
    combinator
    |> concat(
      @parser
      |> unwrap_and_tag(tag_as)
    )
  end

  defp degrees(:north), do: 0.0
  defp degrees(:east), do: 90.0
  defp degrees(:south), do: 180.0
  defp degrees(:west), do: 270.0

  def to_compass_bearing([card]), do: {degrees(card), 45.0}
  def to_compass_bearing([ord1, ord2]), do: {halfway(ord1, ord2), 22.5}

  def to_compass_bearing([inter, ord1, ord2]),
    do: {halfway(ord1, ord2) |> halfway(inter), 11.25}

  defp halfway(dir1, dir2) when is_atom(dir1), do: halfway(degrees(dir1), dir2)
  defp halfway(dir1, dir2) when is_atom(dir2), do: halfway(dir1, degrees(dir2))

  defp halfway(dir1, dir2) when is_number(dir1) and is_number(dir2) do
    [
      {dir1, dir2},
      {dir1 + 360, dir2},
      {dir1, dir2 + 360}
    ]
    |> Enum.min_by(fn {a, b} -> abs(a - b) end)
    |> then(fn {a, b} -> (a + b) / 2 end)
  end
end
