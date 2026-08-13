defmodule Boom.DB.Repo.Migrations.CreateSubdivisions do
  use Ecto.Migration

  def change do
    create table(:subdivisions) do
      add :sector_id, references("sectors"), null: false

      add :name, :string, null: false
      add :local_x, :integer, null: false
      add :local_y, :integer, null: false
      add :global_x, :integer, null: false
      add :global_y, :integer, null: false
      add :geom, :geometry, null: false
    end

    create unique_index(
      :subdivisions,
      [:sector_id, :local_x, :local_y],
      name: "subdivisions_local_coord_index"
    )

    create unique_index(
      :subdivisions, 
      [:global_x, :global_y], 
      name: "subdivisions_global_coord_index"
    )

    execute("CREATE INDEX subdivisions_geom_index ON subdivisions USING GIST (geom)")
  end
end
