defmodule Pristine.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/pristine"

  def project do
    [
      app: :pristine,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      dialyzer: dialyzer(),
      name: "Pristine",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :telemetry],
      mod: {Pristine.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:finch, "~> 0.18"},
      {:sinter, path: "../sinter"},
      {:foundation, path: "../foundation"},
      {:multipart_ex, path: "../multipart_ex"},
      {:telemetry_reporter, path: "../telemetry_reporter"},
      {:tiktoken_ex, path: "../../North-Shore-AI/tiktoken_ex"},
      {:uuid, "~> 1.1"},
      {:mox, "~> 1.1", only: :test},
      {:plug, "~> 1.15"},
      {:plug_cowboy, "~> 2.7", only: [:dev, :test]},
      {:bandit, "~> 1.0", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Manifest-driven hexagonal core for generating Elixir SDKs and services.
    Separates domain logic from transport, retries, telemetry, and serialization
    via ports and adapters, then renders SDK surfaces from declarative manifests.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "Pristine",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/pristine.svg",
      extras: [
        "README.md"
      ],
      groups_for_modules: [
        "Core Pipeline": [
          Pristine,
          Pristine.Pipeline,
          Pristine.Pipeline.Context,
          Pristine.Pipeline.Step
        ],
        Manifest: [
          Pristine.Manifest,
          Pristine.Manifest.Normalizer,
          Pristine.Manifest.Validator
        ],
        "Code Generation": [
          Pristine.Codegen,
          Pristine.Codegen.TypeGenerator,
          Pristine.Codegen.ClientGenerator,
          Pristine.Codegen.ResourceGenerator
        ],
        Ports: [
          Pristine.Ports.Transport,
          Pristine.Ports.Serializer,
          Pristine.Ports.Retry,
          Pristine.Ports.Telemetry,
          Pristine.Ports.Auth,
          Pristine.Ports.CircuitBreaker,
          Pristine.Ports.RateLimit
        ],
        Adapters: [
          Pristine.Adapters.Finch,
          Pristine.Adapters.Jason
        ],
        Types: [
          Pristine.Types,
          Pristine.Schema
        ]
      ]
    ]
  end

  defp package do
    [
      name: "pristine",
      description: description(),
      files: ~w(lib mix.exs README.md assets),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Online documentation" => "https://hexdocs.pm/pristine"
      },
      maintainers: ["nshkrdotcom"],
      exclude_patterns: [
        "priv/plts",
        ".DS_Store"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end
end
