defmodule Boom.Observation.At do
  import Boom.Guards
  alias Boom.Grid.Block
  alias Boom.Observation

  def new(%Block{} = block, target) when is_object_name(target) do
    %Observation{
      type: __MODULE__,
      origin: block,
      target: target
    }
  end

  def build_solution(%Observation{type: __MODULE__}, origin_geom), do: origin_geom

  def command_text(%Observation{
        type: __MODULE__,
        target: target,
        origin: %Block{name: block}
      }),
      do: "#{target} is at #{block}"
end
