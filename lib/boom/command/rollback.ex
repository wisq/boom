defmodule Boom.Command.Rollback do
  alias Boom.Command
  alias Boom.ObservationLog

  def new, do: %Command{module: __MODULE__}

  def run do
    case ObservationLog.rollback() do
      {:ok, obs} ->
        Boom.output([
          IO.ANSI.light_red(),
          "Disabled: ",
          to_string(obs)
        ])

      {:error, :fully_rolled_back} ->
        Boom.output("Nothing to roll back.")
    end
  end
end
