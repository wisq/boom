defmodule Boom.Command.Disable do
  defmodule Parser do
    import NimbleParsec

    def names, do: ["disable", "delete"]
    def usage(cmd), do: "#{cmd} <id>"

    defparsec(
      :parse_args,
      integer(min: 1)
      |> label("observation number")
      |> eos()
      |> reduce({__MODULE__, :to_command, []})
    )

    def to_command([id]), do: Boom.Command.Disable.new(id)
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
