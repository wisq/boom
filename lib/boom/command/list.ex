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

  defmodule ListState do
    defstruct(
      invalidated: MapSet.new(),
      move_superseded: MapSet.new()
    )
  end

  alias Boom.Command
  alias Boom.Observation
  alias Boom.ObservationLog

  def new, do: %Command{module: __MODULE__}

  def run do
    ObservationLog.list_all()
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.map_reduce(
      %ListState{},
      fn %Observation{} = obs, state ->
        output = [colour(obs, invalidated?(state, obs)), to_string(obs)]
        state = apply_to_state(state, obs)
        {output, state}
      end
    )
    |> elem(0)
    |> Enum.reverse()
    |> Enum.intersperse("\n")
    |> Boom.output()
  end

  defp invalidated?(
         %ListState{move_superseded: superseded},
         %Observation{type: Observation.Moving, target: target}
       ),
       do: target in superseded

  defp invalidated?(
         %ListState{invalidated: invalidated},
         %Observation{target: target}
       ),
       do: target in invalidated

  defp apply_to_state(%ListState{} = state, %Observation{
         type: Observation.Invalidate,
         active: true,
         target: target
       }),
       do: %ListState{state | invalidated: MapSet.put(state.invalidated, target)}

  defp apply_to_state(%ListState{} = state, %Observation{
         type: Observation.Moving,
         active: true,
         target: target
       }),
       do: %ListState{state | move_superseded: MapSet.put(state.move_superseded, target)}

  defp apply_to_state(%ListState{} = state, %Observation{}), do: state

  # Active, not invalidated
  def colour(%Observation{active: true}, false), do: IO.ANSI.white()
  # Active, invalidated
  def colour(%Observation{active: true}, true), do: IO.ANSI.light_black()
  # Inactive, not invalidated
  def colour(%Observation{active: false}, false), do: IO.ANSI.light_red()
  # Inactive, invalidated
  def colour(%Observation{active: false}, true), do: IO.ANSI.red()
end
