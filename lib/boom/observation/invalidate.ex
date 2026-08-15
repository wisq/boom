defmodule Boom.Observation.Invalidate do
  alias Boom.Grid.Block
  alias Boom.Observation

  import Boom.ObjectRegistry, only: [is_object_name: 1]
  defguard is_block(b) when is_struct(b, Block)
  defguard is_origin(o) when is_object_name(o) or is_block(o)

  def new(target) when is_object_name(target) do
    %Observation{
      type: __MODULE__,
      origin: nil,
      target: target
    }
  end

  def command_text(%Observation{type: __MODULE__, target: target}), do: "#{target} has moved"
end
