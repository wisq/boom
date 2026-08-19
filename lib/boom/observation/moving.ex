defmodule Boom.Observation.Moving do
  import Boom.Guards
  alias Boom.Observation

  def new(target, {_, _} = bearing, {_, _} = speed, time)
      when is_object_name(target) and is_time(time) do
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
          {speed, speed_error},
          time
        }
      }) do
    [
      target,
      " is moving #{bearing}° ± #{bearing_error}°",
      " at #{speed} ± #{speed_error} knots",
      " since ",
      Time.to_string(time)
    ]
  end

  def build_geometries(
        %Observation{type: __MODULE__, params: {{bearing, bearing_error}, speed, ref_time}},
        start_geom,
        at_time
      ) do
    seconds = time_delta(ref_time, at_time)
    {range, range_error} = apply_speed(speed, seconds)

    [
      Observation.Bearing.new(bearing, bearing_error, "dummy", "dummy")
      |> Observation.Bearing.build_solution(start_geom),
      Observation.Range.new(range, range_error, "dummy", "dummy")
      |> Observation.Range.build_solution(start_geom)
    ]
  end

  defp time_delta(t1, t2) do
    {s1, 0} = Time.to_seconds_after_midnight(t1)
    {s2, 0} = Time.to_seconds_after_midnight(t2)
    secs = s2 - s1
    if secs < 0, do: secs + 86400, else: secs
  end

  @knots_to_mps 1852 / 3600

  defp apply_speed({speed, error}, seconds) do
    metres = speed * @knots_to_mps * seconds
    {metres, metres * error}
  end
end
