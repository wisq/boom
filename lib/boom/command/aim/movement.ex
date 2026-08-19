defmodule Boom.Command.Aim.Movement do
  import Boom.Guards
  alias Boom.Observation
  alias Boom.Grid
  alias Boom.DB.GeoEngine

  def future_geometry(object, %Time{} = time, geom) when is_object_name(object) do
    with {:ok, observation} <- find_moving_observation(object) do
      observation
      |> Observation.Moving.build_geometries(geom, time)
      |> build_solution()
      |> then(fn
        geom when is_geometry(geom) -> {:ok, geom}
        :disjoint -> {:error, :moved_off_map}
      end)
    end
  end

  defp build_solution(geoms) do
    geoms
    |> Enum.reject(fn g -> g == :not_applicable end)
    |> Enum.reduce_while(Grid.grid_geometry(), fn
      :pending, _ -> {:halt, :pending}
      :unknown, _ -> {:halt, :unknown}
      _, :disjoint -> {:halt, :disjoint}
      %{} = geom, %{} = acc -> {:cont, GeoEngine.intersection(geom, acc)}
    end)
  end

  defp find_moving_observation(object) do
    Boom.ObservationLog.entries(object)
    |> Enum.find(fn
      %Observation{type: Observation.Moving, active: true} -> true
      %Observation{} -> false
    end)
    |> then(fn
      %Observation{} = obs -> {:ok, obs}
      nil -> {:error, :no_movement}
    end)
  end
end
