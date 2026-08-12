defmodule Boom.Command.Invalidate do
  alias Boom.Grid.Block
  alias Boom.Command

  import Boom.ObjectRegistry, only: [is_object_name: 1]
  defguard is_block(b) when is_struct(b, Block)
  defguard is_origin(o) when is_object_name(o) or is_block(o)

  def new(target) when is_object_name(target) do
    %Command{
      type: __MODULE__,
      origin: nil,
      target: target
    }
  end
end
