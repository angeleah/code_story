defmodule CodeStory.TestSupport.FakeMeta do
  @moduledoc false
  # Its Inspect impl emits the exact `#Ecto.Schema.Metadata<...>` bytes CodeStory's
  # regexes target — without defining the real `Ecto.Schema.Metadata` atom.
  defstruct [:state, :source]

  defimpl Inspect do
    def inspect(m, _opts) do
      "#Ecto.Schema.Metadata<#{Kernel.inspect(m.state)}, #{Kernel.inspect(m.source)}>"
    end
  end
end

defmodule CodeStory.TestSupport.FakeNotLoaded do
  @moduledoc false
  defstruct [:assoc]

  defimpl Inspect do
    def inspect(n, _opts) do
      "#Ecto.Association.NotLoaded<association #{Kernel.inspect(n.assoc)} is not loaded>"
    end
  end
end

defmodule CodeStory.TestSupport.EctoIsh do
  @moduledoc false
  # Mimics an Ecto schema struct: a real `__meta__` field whose value inspects as
  # `#Ecto.Schema.Metadata<...>`, so `CleanInspect` sees the marker and the compact
  # limit bump applies. Uses the DEFAULT struct Inspect, so it respects `:limit`.
  # Fields inspect in DEFSTRUCT order: __meta__, id, status, kind.
  defstruct [:__meta__, :id, :status, :kind]
end

defmodule CodeStory.TestSupport.EctoIshAssoc do
  @moduledoc false
  # Like EctoIsh but with an unloaded association field, so the `NotLoaded` strip can be
  # exercised through the REAL inspect pipeline (Inspect renders it → `inspect/2` strips
  # it), not just via hand-written strings. Fields inspect in DEFSTRUCT order:
  # __meta__, id, event, status.
  defstruct [:__meta__, :id, :event, :status]
end
