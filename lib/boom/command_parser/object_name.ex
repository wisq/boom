defmodule Boom.CommandParser.ObjectName do
  import NimbleParsec

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
      |> reduce({Boom.CommandParser.Helpers, :recombine, []})
      |> unwrap_and_tag(tag_as)
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
      |> reduce({Boom.CommandParser.Helpers, :recombine, []})
      |> unwrap_and_tag(tag_as)
    )
  end
end
