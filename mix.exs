defmodule CodeStory.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/angeleahdaidone/code_story"

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
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "CodeStory",
      source_url: @source_url
    ]
  end
end
