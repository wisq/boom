defmodule Boom.Command.Describe do
  import Boom.Guards
  alias Boom.Command
  alias Boom.Object

  def new(target) when is_object_name(target) do
    %Command{
      module: __MODULE__,
      args: [target]
    }
  end

  def run(target) do
    Object.describe(target)
    |> Boom.output()
  end
end
