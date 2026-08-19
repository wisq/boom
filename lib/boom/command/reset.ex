defmodule Boom.Command.Reset do
  defmodule Parser do
    import NimbleParsec

    def names, do: ["RESET", "CLEAR"]
    def usage(cmd), do: cmd

    defparsec(
      :parse_args,
      eos()
      |> reduce({__MODULE__, :to_command, []})
    )

    def to_command([]), do: Boom.Command.Reset.new()
  end

  def new, do: %Boom.Command{module: __MODULE__}

  def run do
    Boom.ObjectSupervisor.kill_all()
    Boom.ObservationLog.reset()
    Boom.output("*** All objects and observations deleted. ***")
    # Force a redraw:
    PubSub.publish(:object_registry, {:object_updated, :reset})
  end
end
