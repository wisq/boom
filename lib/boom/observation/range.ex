defmodule Boom.Observation.Range do
  import Boom.Guards
  alias Boom.Grid.Block
  alias Boom.Observation

  def new(range, error, origin, target)
      when is_number(range) and is_number(error) and
             is_origin(origin) and is_object_name(target) do
    %Observation{
      type: __MODULE__,
      params: {range, error},
      origin: origin,
      target: target
    }
  end

  import Ecto.Query, only: [from: 2]
  alias Boom.DB.Repo
  alias Boom.DB.GeoEngine

  def build_solution(%Observation{type: __MODULE__, params: {range, error}}, origin_geom) do
    min_range = range - error
    max_range = range + error

    origin_geom
    |> GeoEngine.split_multipolygon()
    |> Enum.map(fn polygon ->
      from(
        q in fragment(
          "SELECT Range_Ring(?::geometry, ?::double precision, ?::double precision) AS geom",
          ^polygon,
          ^min_range,
          ^max_range
        ),
        select: fragment("geom")
      )
      |> Repo.one()
    end)
    |> Enum.reduce(&GeoEngine.union/2)
  end

  def command_text(%Observation{
        type: __MODULE__,
        target: target,
        params: {range, error},
        origin: origin
      }) do
    "#{target} is range #{range / 1000}km ± #{error}m from #{origin_text(origin)}"
  end

  defp origin_text(%Block{name: name}), do: name
  defp origin_text(name) when is_object_name(name), do: name
end
