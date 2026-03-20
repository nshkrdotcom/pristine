defmodule Pristine.Codegen.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/pristine"

  def project do
    [
      app: :pristine_codegen,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      build_path: "../../_build",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      dialyzer: dialyzer(),
      name: "Pristine Codegen",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:pristine, path: "../pristine_runtime"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"},
      {:sinter, "~> 0.2.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Shared provider compiler, ProviderIR, and rendering package for Pristine-based SDKs.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "Pristine Codegen",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      extras: [
        "README.md",
        "guides/code-generation.md"
      ]
    ]
  end

  defp package do
    [
      name: "pristine_codegen",
      description: description(),
      files: ~w(lib mix.exs README.md guides),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["nshkrdotcom"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "../../_build/plts/core"
    ]
  end
end
