defmodule Boom.DB.Subdivision do
  use Ecto.Schema

  schema "subdivisions" do
    field(:name, :string)
    field(:local_x, :integer)
    field(:local_y, :integer)
    field(:global_x, :integer)
    field(:global_y, :integer)
    field(:geom, Geo.PostGIS.Geometry)
    belongs_to(:sector, Boom.DB.Sector)
  end
end
