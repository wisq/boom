defmodule Boom.CommandParser.Helpers do
  def recombine(parts) do
    parts
    |> Enum.map(fn
      char when is_integer(char) -> <<char>>
      str when is_binary(str) -> str
    end)
    |> Enum.join()
  end
end
