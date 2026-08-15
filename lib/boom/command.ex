defmodule Boom.Command do
  @enforce_keys [:module]
  defstruct(
    module: nil,
    args: []
  )

  alias __MODULE__

  def run(%Command{module: module, args: args}) do
    apply(module, :run, args)
  end
end
