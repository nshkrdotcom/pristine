defmodule Tinkex.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :tinkex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      name: "Tinkex",
      description: "Elixir SDK for the Tinker ML Training Platform",
      dialyzer: [
        plt_add_apps: [:ex_unit],
        flags: [:error_handling, :underspecs]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [coveralls: :test, "coveralls.html": :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Tinkex.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependency - provides ALL infrastructure
      {:pristine, path: "../.."},

      # Pristine's transitive deps are available via pristine
      # But we list them for direct use in domain logic
      {:foundation, path: "../../../foundation"},
      {:sinter, path: "../../../sinter"},
      {:multipart_ex, path: "../../../multipart_ex"},
      {:telemetry_reporter, path: "../../../telemetry_reporter"},

      # ML/Tokenization
      {:nx, "~> 0.9"},
      {:tiktoken_ex, path: "../../../../North-Shore-AI/tiktoken_ex"},

      # HTTP (used directly in some modules)
      {:finch, "~> 0.18"},
      {:jason, "~> 1.4"},

      # Utilities
      {:uuid, "~> 1.1"},
      {:telemetry, "~> 1.2"},

      # Testing
      {:supertester, path: "../../../supertester", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},

      # Code Quality
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
