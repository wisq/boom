defmodule Boom.CommandParser.ObjectName do
  import NimbleParsec
  import Boom.Guards

  object_name_chars =
    [?\s, ?;, ?:]
    |> Enum.map(&{:not, &1})

  @object_first_word utf8_char([?A..?Z, ?a..?z])
                     |> utf8_string(object_name_chars, min: 0)

  @object_next_word string(" ") |> utf8_string(object_name_chars, min: 1)

  def object_name(combinator \\ empty(), tag_as) do
    combinator
    |> concat(
      @object_first_word
      |> repeat(@object_next_word)
      |> reduce({__MODULE__, :build_object_name, []})
      |> unwrap_and_tag(tag_as)
      |> label("object name")
    )
  end

  def object_name_until(combinator \\ empty(), stop_at, tag_as) do
    combinator
    |> concat(
      @object_first_word
      |> repeat(
        lookahead_not(string(stop_at))
        |> concat(@object_next_word)
      )
      |> reduce({__MODULE__, :build_object_name, []})
      |> unwrap_and_tag(tag_as)
      |> label("object name")
    )
  end

  def build_object_name(parts) do
    parts
    |> Boom.CommandParser.Helpers.recombine()
    |> then(&to_object_name/1)
  end

  defp to_object_name("ownship"), do: :ownship
  defp to_object_name("nest"), do: :ownship
  defp to_object_name("iron nest"), do: :ownship
  defp to_object_name(name) when is_object_name(name), do: name
end
