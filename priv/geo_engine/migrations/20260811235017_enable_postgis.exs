defmodule Boom.GeoEngine.Migrations.EnablePostgis do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS postgis")
    execute("CREATE EXTENSION IF NOT EXISTS postgis_sfcgal")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS postgis_sfcgal")
    execute("DROP EXTENSION IF EXISTS postgis")
  end
end
