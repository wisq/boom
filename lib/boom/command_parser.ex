defmodule Boom.CommandParser do
  require Logger
  alias Boom.Command
  alias Boom.Grid
  alias Boom.Grid.Block

  alias Boom.CommandParser.Compass

  def parse(line) do
    line
    |> String.split()
    |> parse_words()
  end

  defp parse_words(words) do
    case lookahead(words, "is") do
      {name, ["is", "at" | rest]} -> parse_object(name) |> parse_at(rest)
      {name, ["is", "in" | rest]} -> parse_object(name) |> parse_at(rest)
      {name, ["is", "bearing" | rest]} -> parse_object(name) |> parse_bearing(:degrees, rest)
      {name, ["is", "due" | rest]} -> parse_object(name) |> parse_bearing(:compass, rest)
      _ -> :fail
    end
  end

  defp lookahead(words, target, skip \\ 1)

  defp lookahead([], _, _), do: :no_match
  defp lookahead([target | _] = match, target, 0), do: {[], match}

  defp lookahead([head | rest], target, skip) do
    case lookahead(rest, target, max(skip - 1, 0)) do
      {before, match} -> {[head | before], match}
      :no_match -> :no_match
    end
  end

  defp parse_at(name, sector) do
    with {:ok, %Block{} = block} = parse_block(sector) do
      Command.At.new(block, name)
    end
  end

  defp parse_bearing(name, type, rest) when type in [:degrees, :compass] do
    with {direction, ["from" | origin]} <- lookahead(rest, "from"),
         {:ok, bearing, error} <- parse_direction(type, direction),
         origin <- parse_object(origin) do
      IO.inspect({:bearing, name, bearing, error, origin})
    end
  end

  defp parse_object(["iron", "nest"]), do: :ownship
  defp parse_object(["nest"]), do: :ownship
  defp parse_object(other), do: Enum.join(other, " ")

  defp parse_block(words) do
    name = words |> Enum.join(" ")

    case Grid.block_by_name(name) do
      {:ok, %Block{}} = success -> success
      :error -> {:error, :block_not_found, name}
    end
  end

  defp parse_direction(:degrees, words), do: parse_degrees(words)
  defp parse_direction(:compass, words), do: Compass.parse(words)

  @bearing_regex ~r/^
    ([0-9]+)      # integer degrees
    (?:           # decimal is optional
      [., ]       # we allow a variety of separators
      ([0-9]+)    # decimal places
    )?
    [\s°º]*       # ignore degree symbols
    (?:\s?deg(?:rees?))?   # ignore english words
    \s*(.*)       # log and ignore other junk
  $/x

  defp parse_degrees(words) do
    string = Enum.join(words, " ")

    with [_, integer, decimal, junk] <- Regex.run(@bearing_regex, string) do
      error = 0.5 * 10 ** -String.length(decimal)
      bearing = String.to_float("#{integer}.#{decimal}0")
      unless junk == "", do: Logger.debug("Ignoring junk after bearing: #{inspect(junk)}")
      {:ok, bearing, error}
    else
      nil -> {:error, :invalid_bearing, string}
    end
  end
end
