defmodule Boom.Observation.Moving do
  import Boom.Guards
  alias Boom.Observation

  def new(target, {_, _} = bearing, {_, _} = speed, time)
      when (is_object_name(target) and is_struct(time, Time)) or is_nil(time) do
    %Observation{
      type: __MODULE__,
      params: {bearing, speed, time},
      origin: nil,
      target: target
    }
  end

  def command_text(%Observation{
        type: __MODULE__,
        target: target,
        params: {
          {bearing, bearing_error},
          {speed, _speed_error},
          time
        }
      }) do
    [
      target,
      " is moving #{bearing}° ± #{bearing_error}°",
      " at #{speed} knots",
      case time do
        nil -> []
        %Time{} = t -> [" since ", Time.to_string(t)]
      end
    ]
  end
end
