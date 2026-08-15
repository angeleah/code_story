defmodule CodeStory.TestSupport.FakeRepo do
  @moduledoc false
  # Duck-types an Ecto repo. The ONLY signal CodeStory uses to detect a repo is
  # `function_exported?(mod, :__adapter__, 0)` — no compile-time Ecto dependency.
  def __adapter__, do: :fake_adapter
end

defmodule CodeStory.TestSupport.NotARepo do
  @moduledoc false
  def hello, do: :world
end
