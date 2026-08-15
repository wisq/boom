defmodule Boom.Defines do
  # Definitions needed by other modules at compile time.
  #
  # Mainly, things used in guards, but that we don't want to put in their most
  # relevant module, because that module also needs those guards.
  def special_object_names, do: [:ownship]
  def solution_errors, do: [:pending, :unknown, :disjoint]
end
