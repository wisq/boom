defmodule Boom.Command.EmergencyMove do
  defmodule Parser do
    import NimbleParsec
    import Boom.CommandParser.Block

    def usage, do: "emergency move [to <block>] / move [to <block>]"

    def names, do: ["emergency move", "move"]

    defparsec(
      :parse_args,
      optional(
        ignore(string("to "))
        |> block(:block)
      )
      |> eos()
      |> reduce({__MODULE__, :to_command, []})
    )

    def to_command([]), do: Boom.Command.EmergencyMove.new(nil)
    def to_command(block: block), do: Boom.Command.EmergencyMove.new(block)
  end

  alias Boom.Grid.Block
  alias Boom.Command
  alias Boom.Observation

  def new(%Block{} = block) do
    observations = [
      Observation.Invalidate.new(:ownship),
      Observation.At.new(block, :ownship)
    ]

    %Command{
      module: __MODULE__,
      args: [observations]
    }
  end

  def new(nil) do
    observations = [Observation.Invalidate.new(:ownship)]

    %Command{
      module: __MODULE__,
      args: [observations]
    }
  end

  def run([%Observation{} | _] = obslist) do
    Boom.ObservationLog.add(obslist)
  end
end
