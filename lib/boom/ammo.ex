defmodule Boom.Ammo do
  @enforce_keys [:name, :blast_radius]
  defstruct(
    name: nil,
    blast_radius: nil,
    auto_suggest: false
  )
end
