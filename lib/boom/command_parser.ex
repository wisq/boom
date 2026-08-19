defmodule Boom.CommandParser do
  import NimbleParsec
  require Logger

  alias Boom.Command

  defmodule ParseError do
    defexception [:message]
  end

  commands = [
    Command.Reset,
    Command.List,
    Command.Disable,
    Command.Enable,
    Command.Rollback,
    Command.Describe,
    Command.Aim
  ]

  command_names =
    commands
    |> Enum.flat_map(fn module ->
      parser = Module.concat(module, "Parser")
      parser.names() |> Enum.map(fn n -> {n, parser} end)
    end)

  defparsecp(
    :parse_command_name,
    choice(
      command_names
      |> Enum.map(fn {name, module} ->
        string(name)
        |> replace({name, module})
        |> label(name)
      end)
    )
    |> choice([
      ignore(string(" ")),
      eos()
    ])
  )

  def parse(line) do
    line = line |> String.replace(~r/\s+/, " ")

    case parse_command_name(line) do
      {:ok, [{name, module}], args, _, _, _} -> parse_command(module, name, args)
      {:error, _, _, _, _, _} -> parse_observation(line)
    end
  end

  defp parse_command(module, name, args) do
    try do
      case module.parse_args(args) do
        {:ok, [%Command{} = cmd], "", _, _, _} ->
          {:ok, cmd}

        {:error, msg, rest, _, _, _} ->
          {:error, ["Error processing ", name, " command: ", msg, ", got ", inspect(rest)]}
      end
    rescue
      e in ParseError ->
        {:error, e.message}

      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        {:error, ["Got ", inspect(e), " while processing ", name, " command."]}
    end
  end

  defp parse_observation(line) do
    try do
      case Command.Observe.Parser.parse_observation(line) do
        {:ok, [%Command{} = cmd], "", _, _, _} ->
          {:ok, cmd}

        {:error, ~s{expected string " is "}, _, _, _, _} ->
          {:error, "Unknown command."}

        {:error, msg, rest, _, _, _} ->
          {:error, ["Error processing observation: ", msg, ", got ", inspect(rest)]}
      end
    rescue
      e in ParseError ->
        {:error, e.message}

      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        {:error, ["Got ", inspect(e), " while processing observation."]}
    end
  end
end
