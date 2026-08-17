defmodule Boom.CommandParser do
  require Logger

  alias Boom.Observation
  alias Boom.Grid
  alias Boom.Grid.Block
  alias Boom.Ammo
  alias Boom.Command
  alias Boom.CommandParser.Compass

  def parse(cmd) do
    cmd
    |> String.split()
    |> parse_words()
    |> then(fn
      %Command{} = cmd -> {:ok, cmd}
      {:error, :unknown_command} -> {:error, "Unknown command."}
      {:error, _} = err -> err
    end)
  end

  defp parse_words(["list"]), do: Command.List.new()
  defp parse_words(["rollback"]), do: Command.Rollback.new()
  defp parse_words(["undo"]), do: Command.Rollback.new()
  defp parse_words(["emergency", "move" | rest]), do: parse_invalidate(:ownship, rest)

  defp parse_words(["aim", "at" | name]), do: parse_object(name) |> parse_aim(nil)
  defp parse_words(["aim", ammo, "at" | name]), do: parse_object(name) |> parse_aim(ammo)
  defp parse_words(["fire", "at" | name]), do: parse_object(name) |> parse_aim(nil)
  defp parse_words(["fire", ammo, "at" | name]), do: parse_object(name) |> parse_aim(ammo)

  defp parse_words(["target" | rest] = words) do
    case lookahead(rest, ["with"]) do
      {name, ["with" | ammo]} ->
        parse_object(name) |> parse_aim(ammo)

      :no_match ->
        case parse_fallback(words) do
          %Command{} = cmd -> cmd
          {:error, :unknown_command} -> parse_object(rest) |> parse_aim(nil)
        end
    end
  end

  defp parse_words(["disable", idstr]) do
    with {id, ""} <- Integer.parse(idstr) do
      Command.Disable.new(id)
    else
      _ -> {:error, ["Not an integer: ", inspect(idstr)]}
    end
  end

  defp parse_words(words), do: parse_fallback(words)

  defp parse_fallback(words) do
    case lookahead(words, ["is", "has"]) do
      {name, ["is", "at" | rest]} -> parse_object(name) |> parse_at(rest)
      {name, ["is", "in" | rest]} -> parse_object(name) |> parse_at(rest)
      {name, ["is", "bearing" | rest]} -> parse_object(name) |> parse_bearing(:degrees, rest)
      {name, ["is", "due" | rest]} -> parse_object(name) |> parse_bearing(:compass, rest)
      {name, ["is", "range" | rest]} -> parse_object(name) |> parse_range(rest)
      {name, ["is" | rest]} -> parse_object(name) |> parse_is(rest)
      {name, ["has", "moved" | rest]} -> parse_object(name) |> parse_invalidate(rest)
      _ -> {:error, :unknown_command}
    end
  end

  defp lookahead(words, targets, skip \\ 1)

  defp lookahead(words, target, skip) when is_binary(target) do
    lookahead(words, [target], skip)
  end

  defp lookahead([], _, _), do: :no_match

  defp lookahead([head | rest] = match, targets, skip) do
    if head in targets do
      {[], match}
    else
      case lookahead(rest, targets, max(skip - 1, 0)) do
        {before, match} -> {[head | before], match}
        :no_match -> :no_match
      end
    end
  end

  defp parse_at(target, grid) do
    with {:ok, %Block{} = block} = parse_block(grid) do
      Command.Observe.new([
        Observation.At.new(block, target)
      ])
    end
  end

  defp parse_bearing(target, type, rest) when type in [:degrees, :compass] do
    separator =
      case type do
        :compass -> ["from", "of"]
        :degrees -> ["from"]
      end

    with {direction, [_from_of | origin]} <- lookahead(rest, separator),
         {:ok, bearing, error} <- parse_direction(type, direction),
         origin <- parse_object(origin) do
      Command.Observe.new([
        Observation.Bearing.new(bearing, error, origin, target)
      ])
    end
  end

  defp parse_range(target, rest) do
    with {range, ["from" | origin]} <- lookahead(rest, "from"),
         {:ok, range, error} <- parse_range(range),
         origin <- parse_object(origin) do
      Command.Observe.new([
        Observation.Range.new(range, error, origin, target)
      ])
    end
  end

  @is_range ~r/([0-9]|\b)(
    k?m
    | (kilo)?met(re|er)s?
  )\b/x

  @is_degrees ~r/
    [°º]   # degree symbols
    | ([0-9]|\b) deg(ree)s? \b
  /x

  defp parse_is(target, rest) do
    with {before, [_from | _]} <- lookahead(rest, ["from", "of"]) do
      string = Enum.join(before, " ")

      cond do
        string =~ @is_range -> parse_range(target, rest)
        string =~ @is_degrees -> parse_bearing(target, :degrees, rest)
        is_compass_direction(string) -> parse_bearing(target, :compass, rest)
        true -> {:error, "Not sure if #{inspect(string)} is a bearing or range."}
      end
    end
  end

  defp parse_invalidate(target, []) do
    Command.Observe.new([
      Observation.Invalidate.new(target)
    ])
  end

  defp parse_invalidate(target, ["to" | grid]) do
    with {:ok, %Block{} = block} = parse_block(grid) do
      Command.Observe.new([
        Observation.Invalidate.new(target),
        Observation.At.new(block, target)
      ])
    end
  end

  defp parse_aim(target, nil) do
    Command.Aim.new(target, Ammo.Types.auto_suggest())
  end

  defp parse_aim(target, ammo) do
    with {:ok, ammo} <- parse_ammo(ammo) do
      Command.Aim.new(target, [ammo])
    else
      {:error, :unknown_ammo, name} -> {:error, "Unknown ammo: #{inspect(name)}"}
    end
  end

  defp parse_object(["iron", "nest"]), do: :ownship
  defp parse_object(["nest"]), do: :ownship
  defp parse_object(["ownship"]), do: :ownship

  defp parse_object(words) do
    name = Enum.join(words, " ")

    case Grid.block_by_name(name) do
      {:ok, %Block{} = block} -> block
      :error -> name
    end
  end

  defp parse_block(words) do
    name = words |> Enum.join(" ")

    case Grid.block_by_name(name) do
      {:ok, %Block{}} = success -> success
      :error -> {:error, ["Grid block not found: ", name]}
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
    [\s°º]*       # ignore degree symbols (correct or otherwise)
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
      nil -> {:error, ["Invalid bearing: ", string]}
    end
  end

  @range_regex ~r/^
    ([0-9]+)      # integer units
    (?:           # decimal is optional
      [., ]       # we allow a variety of separators
      ([0-9]+)    # decimal places
    )?
    \s?
    (k?m|(?:kilo)?met(?:re|er)s?)?   # optional units
    \s*(.*)       # log and ignore other junk
  $/x

  defp parse_range(words) do
    string = Enum.join(words, " ")

    with [_, integer, decimal, units, junk] <- Regex.run(@range_regex, string) do
      error = 0.5 * 10 ** -String.length(decimal)
      range = String.to_float("#{integer}.#{decimal}0")
      unless junk == "", do: Logger.debug("Ignoring junk after range: #{inspect(junk)}")

      case units do
        "m" <> _ -> {:ok, range, error}
        "k" <> _ -> {:ok, range * 1000, error * 1000}
        "" -> {:ok, range * 1000, error * 1000}
      end
    else
      nil -> {:error, ["Invalid range: ", inspect(string)]}
    end
  end

  defp is_compass_direction(str) do
    case Compass.parse(str) do
      {:ok, _bearing, _error} -> true
      {:error, _err, _str} -> false
    end
  end

  defp parse_ammo(words) when is_list(words), do: words |> Enum.join(" ") |> parse_ammo()

  defp parse_ammo(name) when is_binary(name) do
    case Ammo.Types.fetch(name) do
      {:ok, %Ammo{} = ammo} -> {:ok, ammo}
      :error -> {:error, :unknown_ammo, name}
    end
  end
end
