defmodule Boom.DB.Sector do
  use Ecto.Schema

  schema "sectors" do
    field(:name, :string)
    field(:x, :integer)
    field(:y, :integer)
    field(:geom, Geo.PostGIS.Geometry)
    has_many(:subdivisions, Boom.DB.Subdivision, preload_order: [:local_x, :local_y])
  end
end
