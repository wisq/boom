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

  north_char = string("n") |> replace(:north)
  south_char = string("s") |> replace(:south)
  east_char = string("e") |> replace(:east)
  west_char = string("w") |> replace(:west)

  cardinal_char = choice([north_char, south_char, east_char, west_char])
  ordinal_chars = choice([north_char, south_char]) |> choice([east_char, west_char])
  subordinal_chars = cardinal_char |> concat(ordinal_chars)

  defparsecp(
    :parse_string,
    choice([
      subordinal_words,
      subordinal_chars,
      ordinal_words,
      ordinal_chars,
      cardinal_word,
      cardinal_char
    ])
    |> eos()
  )

  def parse(words) when is_list(words), do: words |> Enum.join() |> parse()

  def parse(str) when is_binary(str) do
    str
    |> String.trim()
    |> String.downcase()
    |> parse_string()
    |> then(fn
      {:ok, atoms, "", _, _, _} -> parse_atoms(atoms)
      {:error, _, _, _, _, _} -> {:error, :bad_compass_direction, str}
    end)
  end

  defp degrees(:north), do: 0.0
  defp degrees(:east), do: 90.0
  defp degrees(:south), do: 180.0
  defp degrees(:west), do: 270.0

  defp parse_atoms([card]), do: {:ok, degrees(card), 45.0}
  defp parse_atoms([ord1, ord2]), do: {:ok, halfway(ord1, ord2), 22.5}
  defp parse_atoms([inter, ord1, ord2]), do: {:ok, halfway(ord1, ord2) |> halfway(inter), 11.25}

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
