defmodule Boom.Command.Reset do
  alias Boom.Command

  def new, do: %Command{module: __MODULE__}

  def run do
    Boom.ObjectSupervisor.kill_all()
    Boom.ObservationLog.reset()
    Boom.output("*** All objects and observations deleted. ***")
    # Force a redraw:
    PubSub.publish(:object_registry, {:object_updated, :reset})
  end
end
