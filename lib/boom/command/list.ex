defmodule Boom.Command.List do
  defmodule Parser do
    import NimbleParsec

    def names, do: ["list"]
    def usage(cmd), do: cmd

    defparsec(
      :parse_args,
      eos()
      |> reduce({__MODULE__, :to_command, []})
    )

    def to_command([]), do: Boom.Command.List.new()
  end

  alias Boom.Command
  alias Boom.Observation
  alias Boom.ObservationLog

  def new, do: %Command{module: __MODULE__}

  def run do
    ObservationLog.list_all()
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.map_reduce(
      MapSet.new(),
      fn %Observation{target: target, type: type, active: active} = obs, invalidated ->
        output = [colour(obs, target in invalidated), to_string(obs)]

        case {type, active} do
          {Observation.Invalidate, true} -> {output, MapSet.put(invalidated, target)}
          _ -> {output, invalidated}
        end
      end
    )
    |> elem(0)
    |> Enum.reverse()
    |> Enum.intersperse("\n")
    |> Boom.output()
  end

  # Active, not invalidated
  def colour(%Observation{active: true}, false), do: IO.ANSI.white()
  # Active, invalidated
  def colour(%Observation{active: true}, true), do: IO.ANSI.light_black()
  # Inactive, not invalidated
  def colour(%Observation{active: false}, false), do: IO.ANSI.light_red()
  # Inactive, invalidated
  def colour(%Observation{active: false}, true), do: IO.ANSI.red()
end
