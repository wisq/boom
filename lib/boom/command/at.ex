defmodule Boom.Command.At do
  alias Boom.Grid.Block
  alias Boom.Command

  import Boom.ObjectRegistry, only: [is_object_name: 1]
  defguard is_block(b) when is_struct(b, Block)
  defguard is_origin(o) when is_object_name(o) or is_block(o)

  def new(%Block{} = block, target) when is_object_name(target) do
    %Command{
      type: __MODULE__,
      origin: block,
      target: target
    }
  end

  def build_geometry(%Command{type: __MODULE__}, geom), do: geom
end
