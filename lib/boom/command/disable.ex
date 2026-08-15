defmodule Boom.Command.Disable do
  alias Boom.Command
  alias Boom.ObservationLog

  def new(obs_id) when is_integer(obs_id) do
    %Command{
      module: __MODULE__,
      args: [obs_id]
    }
  end

  def run(obs_id) when is_integer(obs_id) do
    case ObservationLog.disable(obs_id) do
      {:ok, obs} ->
        Boom.output([
          IO.ANSI.light_red(),
          "Disabled: ",
          to_string(obs)
        ])

      {:error, :not_found} ->
        Boom.output("Command #{obs_id} not found.")

      {:error, :already_disabled} ->
        Boom.output("Command #{obs_id} already disabled.")
    end
  end
end
