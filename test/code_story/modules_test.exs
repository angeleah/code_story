defmodule CodeStory.ModulesTest do
  use ExUnit.Case, async: true

  describe "camelize_app_name/1" do
    test "converts app atom to camelized module prefix" do
      assert CodeStory.Modules.camelize_app_name(:my_app) == "MyApp"
      assert CodeStory.Modules.camelize_app_name(:code_story) == "CodeStory"
      assert CodeStory.Modules.camelize_app_name(:phoenix_live_view) == "PhoenixLiveView"
    end
  end

  describe "ecto_repos/1" do
    alias CodeStory.TestSupport.{FakeRepo, NotARepo}

    test "detects modules that export __adapter__/0 and excludes those that don't" do
      assert CodeStory.Modules.ecto_repos([FakeRepo, NotARepo]) == [FakeRepo]
    end

    test "detects a repo that is loadable but not currently loaded (Code.ensure_loaded? guard)" do
      # Force the unloaded-but-loadable state a real repo can be in when detection
      # runs before the tracer forces module loading.
      :code.delete(FakeRepo)
      :code.purge(FakeRepo)
      refute :erlang.module_loaded(FakeRepo)

      assert CodeStory.Modules.ecto_repos([FakeRepo]) == [FakeRepo]
    end
  end

  describe "detect/0" do
    test "returns a list of modules" do
      modules = CodeStory.Modules.detect()
      assert is_list(modules)
    end

    test "excludes CodeStory's core modules" do
      modules = CodeStory.Modules.detect()
      refute CodeStory in modules
      refute CodeStory.Modules in modules
      refute CodeStory.Tracer in modules
      refute CodeStory.Collector in modules
      refute CodeStory.Formatter in modules
      refute CodeStory.Args in modules
    end

    test "includes non-core CodeStory modules when loaded" do
      # Ensure the module is loaded by calling it
      _ = CodeStory.TestSupport.SampleModule.add(1, 2)
      modules = CodeStory.Modules.detect()
      assert CodeStory.TestSupport.SampleModule in modules
    end

    test "includes the host app's Web namespace (MyAppWeb-style modules)" do
      # App :code_story -> prefix "CodeStory" -> Web namespace "CodeStoryWeb".
      # Phoenix apps put LiveViews/controllers under MyAppWeb, which shares no
      # module-split head with MyApp — detect/0 must include both namespaces.
      true = Code.ensure_loaded?(CodeStoryWeb.SampleWebModule)
      modules = CodeStory.Modules.detect()
      assert CodeStoryWeb.SampleWebModule in modules
    end

    test "excludes standard library modules" do
      modules = CodeStory.Modules.detect()
      refute Kernel in modules
      refute Enum in modules
      refute String in modules
    end

    test "excludes dependency modules" do
      modules = CodeStory.Modules.detect()
      refute ExDoc in modules
    end
  end
end
