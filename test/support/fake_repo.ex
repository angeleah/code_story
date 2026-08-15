defmodule CodeStory.TestSupport.FakeRepo do
  @moduledoc false
  # Duck-types an Ecto repo. The ONLY signal CodeStory uses to detect a repo is
  # `function_exported?(mod, :__adapter__, 0)` — no compile-time Ecto dependency.
  def __adapter__, do: :fake_adapter

  # A public repo call with an interior helper. When FakeRepo is treated as a
  # boundary, `build_result/1` (the interior) is suppressed; when not, it shows.
  def get(id), do: build_result(id)
  defp build_result(id), do: {:ok, id}
end

defmodule CodeStory.TestSupport.NotARepo do
  @moduledoc false
  def hello, do: :world
end
