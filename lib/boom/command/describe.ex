defmodule Boom.Command.Describe do
  defmodule Parser do
    import NimbleParsec
    import Boom.CommandParser.ObjectName

    def names, do: ["describe", "show", "where is"]
    def usage(cmd), do: "#{cmd} <object>"

    defparsec(
      :parse_args,
      object_name(:target)
      |> eos()
      |> reduce({__MODULE__, :to_command, []})
    )

    def to_command(target: target), do: Boom.Command.Describe.new(target)
  end

  import Boom.Guards

  def new(target) when is_object_name(target) do
    %Boom.Command{
      module: __MODULE__,
      args: [target]
    }
  end

  def run(target) do
    Boom.Object.describe(target)
    |> Boom.output()
  end
end
