defmodule Command do
  @enforce_keys [:command, :origin, :target]
  defstruct(
    [
      id: nil
    ] ++ Enum.map(@enforce_keys, &{&1, nil})
  )

  alias Boom.Grid.Block

  import Boom.ObjectRegistry, only: [is_object_name: 1]
  defguard is_block(b) when is_struct(b, Block)
  defguard is_origin(o) when is_object_name(o) or is_block(o)

  def at(%Block{} = block, target) when is_object_name(target) do
    %Command{
      command: :at,
      origin: block,
      target: target
    }
  end

  def bearing(bearing, error, origin, target)
      when is_number(bearing) and is_number(error) and
             is_origin(origin) and is_object_name(target) do
    %Command{
      command: {:bearing, bearing, error},
      origin: origin,
      target: target
    }
  end

  def range(range, error, origin, target)
      when is_number(range) and is_number(error) and
             is_origin(origin) and is_object_name(target) do
    %Command{
      command: {:range, range, error},
      origin: origin,
      target: target
    }
  end

  def invalidate(target) when is_object_name(target) do
    %Command{
      command: :invalidate,
      origin: nil,
      target: target
    }
  end
end
