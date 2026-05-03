Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)

defmodule Pristine.Codegen.MixProject do
  use Mix.Project

  alias Pristine.Build.DependencyResolver

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
      test_ignore_filters: test_ignore_filters(),
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
      DependencyResolver.pristine_runtime(),
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"},
      {:sinter, "~> 0.3.1"},
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

  defp test_ignore_filters do
    [
      "test/fixtures/golden/widget_api/generated/client.ex",
      "test/fixtures/golden/widget_api/generated/runtime_schema.ex",
      "test/fixtures/golden/widget_api/generated/types/widget.ex",
      "test/fixtures/golden/widget_api/generated/widgets.ex",
      "test/support/provider_fixture.exs"
    ]
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
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: ["guides/code-generation.md"]
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
