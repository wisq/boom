defmodule Boom.DB.Repo.Migrations.CreateSectors do
  use Ecto.Migration

  def change do
    create table(:sectors) do
      add :name, :string, null: false
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :geom, :geometry, null: false
    end

    create unique_index(:sectors, :name)
    create unique_index(:sectors, [:x, :y], name: "sectors_coord_index")
  end
end
