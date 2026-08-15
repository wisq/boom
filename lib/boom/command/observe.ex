defmodule Boom.Command.Observe do
  alias Boom.Command
  alias Boom.Observation
  alias Boom.ObservationLog

  def new([%Observation{} | _] = observations) do
    %Command{
      module: __MODULE__,
      args: [observations]
    }
  end

  def run([%Observation{} | _] = obslist) do
    ObservationLog.add(obslist)
  end
end
