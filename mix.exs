defmodule CodeStory.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/angeleah/code_story"

  def project do
    [
      app: :code_story,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "CodeStory",
      description:
        "A code comprehension tool that traces user-defined function calls as a nested call tree with named arguments and return values.",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "code_story",
      licenses: ["Apache-2.0"],
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE),
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", {"LICENSE", [title: "License"]}],
      groups_for_modules: [
        "Public API": [CodeStory, CodeStory.Encoder, CodeStory.Fold],
        Internals: [
          CodeStory.Args,
          CodeStory.Collector,
          CodeStory.Formatter,
          CodeStory.Modules,
          CodeStory.Tracer
        ]
      ]
    ]
  end
end
