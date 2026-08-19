defmodule Boom.Command.Enable do
  defmodule Parser do
    import NimbleParsec

    def names, do: ["enable", "undelete"]
    def usage(cmd), do: "#{cmd} <id>"

    defparsec(
      :parse_args,
      integer(min: 1)
      |> eos()
      |> reduce({__MODULE__, :to_command, []})
    )

    def to_command([id]), do: Boom.Command.Enable.new(id)
  end

  alias Boom.Command
  alias Boom.ObservationLog

  def new(obs_id) when is_integer(obs_id) do
    %Command{
      module: __MODULE__,
      args: [obs_id]
    }
  end

  def run(obs_id) when is_integer(obs_id) do
    case ObservationLog.enable(obs_id) do
      {:ok, obs} ->
        Boom.output([
          IO.ANSI.light_green(),
          "Enabled: ",
          to_string(obs)
        ])

      {:error, :not_found} ->
        Boom.output("Command #{obs_id} not found.")

      {:error, :already_enabled} ->
        Boom.output("Command #{obs_id} already enabled.")
    end
  end
end
