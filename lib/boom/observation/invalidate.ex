defmodule Boom.Observation.Invalidate do
  import Boom.Guards
  alias Boom.Observation

  def new(target) when is_object_name(target) do
    %Observation{
      type: __MODULE__,
      origin: nil,
      target: target
    }
  end

  def command_text(%Observation{type: __MODULE__, target: target}), do: "#{target} has moved"
end
