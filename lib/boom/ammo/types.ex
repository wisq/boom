defmodule Boom.Ammo.Types do
  alias Boom.Ammo

  @ammo_types [
    %Ammo{name: "DRIL", blast_radius: 70, auto_suggest: true},
    %Ammo{name: "AP", blast_radius: 135, auto_suggest: true},
    %Ammo{name: "HE", blast_radius: 270, auto_suggest: true},
    %Ammo{name: "HCHE", blast_radius: 630, auto_suggest: true},
    %Ammo{name: "STAR", blast_radius: 12740}
  ]

  @types_by_name Map.new(@ammo_types, &{&1.name, &1})

  @auto_suggest @ammo_types
                |> Enum.filter(& &1.auto_suggest)
                |> Enum.sort_by(& &1.blast_radius)

  def fetch(name), do: @types_by_name |> Map.fetch(String.upcase(name))
  def auto_suggest, do: @auto_suggest
end
