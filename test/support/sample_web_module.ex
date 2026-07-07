defmodule CodeStoryWeb.SampleWebModule do
  @moduledoc false

  # Stands in for a Phoenix `MyAppWeb.*` module: app :code_story -> prefix
  # "CodeStory" -> Web namespace "CodeStoryWeb". Used to verify that
  # CodeStory.Modules.detect/0 includes the host app's Web namespace.

  def render_greeting(name), do: "Hello from the web, #{name}!"
end
