defmodule Boom.Observation.At do
  alias Boom.Grid.Block
  alias Boom.Observation

  import Boom.ObjectRegistry, only: [is_object_name: 1]
  defguard is_block(b) when is_struct(b, Block)
  defguard is_origin(o) when is_object_name(o) or is_block(o)

  def new(%Block{} = block, target) when is_object_name(target) do
    %Observation{
      type: __MODULE__,
      origin: block,
      target: target
    }
  end

  def build_geometry(%Observation{type: __MODULE__}, geom), do: geom

  def command_text(%Observation{
        type: __MODULE__,
        target: target,
        origin: %Block{name: block}
      }),
      do: "#{target} is at #{block}"
end
