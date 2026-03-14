defmodule Pristine.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/pristine"

  # defp local_or_github(app, path, github, opts \\ []) do
  #   if File.dir?(path) do
  #     {app, [path: path] ++ opts}
  #   else
  #     {app, [github: github] ++ opts}
  #   end
  # end

  def project do
    [
      app: :pristine,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: ["test"],
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

  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

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
      {:nimble_options, "~> 1.1"},
      {:yaml_elixir, "~> 2.12"},
      {:oauth2, "~> 2.1", optional: true, runtime: false},
      {:telemetry, "~> 1.4"},
      {:finch, "~> 0.21"},
      {:sinter, "~> 0.2.0"},
      {:foundation, "~> 0.2.1"},
      {:multipart_ex, "~> 0.1.0"},
      {:telemetry_reporter, "~> 0.1.0", optional: true, runtime: false},
      {:tiktoken_ex, "~> 0.2.0", optional: true, runtime: false},

      ### OpenAPI Generator
      {:oapi_generator,
       github: "nshkrdotcom/open-api-generator", only: [:dev, :test], runtime: false},
      {:uuid, "~> 1.1"},
      {:mox, "~> 1.2", only: :test},
      {:plug, "~> 1.19", optional: true, runtime: false},
      {:plug_cowboy, "~> 2.8", only: [:dev, :test]},
      {:bandit, "~> 1.10", optional: true, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
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
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "guides/getting-started.md",
        "guides/foundation-runtime.md",
        "guides/architecture.md",
        "guides/manifests.md",
        "guides/ports-and-adapters.md",
        "guides/code-generation.md",
        "guides/streaming.md",
        "guides/pipeline.md"
      ],
      groups_for_extras: [
        Introduction: [
          "README.md",
          "CHANGELOG.md",
          "guides/getting-started.md",
          "guides/foundation-runtime.md"
        ],
        Architecture: [
          "guides/architecture.md",
          "guides/ports-and-adapters.md",
          "guides/pipeline.md"
        ],
        "API Definition": [
          "guides/manifests.md",
          "guides/code-generation.md"
        ],
        Features: [
          "guides/streaming.md"
        ]
      ],
      groups_for_modules: [
        "Core Pipeline": [
          Pristine,
          Pristine.Profiles.Foundation,
          Pristine.Core.Pipeline,
          Pristine.Core.Context,
          Pristine.Core.Request,
          Pristine.Core.Response,
          Pristine.Core.StreamResponse
        ],
        Manifest: [
          Pristine.Manifest,
          Pristine.Manifest.Loader,
          Pristine.Manifest.Schema,
          Pristine.Manifest.Endpoint
        ],
        "Code Generation": [
          Pristine.Codegen,
          Pristine.Codegen.Elixir,
          Pristine.Codegen.Type,
          Pristine.Codegen.Resource
        ],
        OAuth2: [
          Pristine.OAuth2,
          Pristine.OAuth2.AuthorizationRequest,
          Pristine.OAuth2.Browser,
          Pristine.OAuth2.CallbackServer,
          Pristine.OAuth2.Error,
          Pristine.OAuth2.Interactive,
          Pristine.OAuth2.PKCE,
          Pristine.OAuth2.Provider,
          Pristine.OAuth2.Token
        ],
        Streaming: [
          Pristine.Streaming.Event,
          Pristine.Streaming.SSEDecoder
        ],
        Ports: [
          Pristine.Ports.Transport,
          Pristine.Ports.StreamTransport,
          Pristine.Ports.Serializer,
          Pristine.Ports.Auth,
          Pristine.Ports.Retry,
          Pristine.Ports.CircuitBreaker,
          Pristine.Ports.RateLimit,
          Pristine.Ports.Telemetry,
          Pristine.Ports.Compression,
          Pristine.Ports.Multipart,
          Pristine.Ports.Tokenizer,
          Pristine.Ports.Semaphore,
          Pristine.Ports.BytesSemaphore,
          Pristine.Ports.Future,
          Pristine.Ports.PoolManager,
          Pristine.Ports.Streaming
        ],
        "Transport Adapters": [
          Pristine.Adapters.Transport.Finch,
          Pristine.Adapters.Transport.FinchStream
        ],
        "Serializer Adapters": [
          Pristine.Adapters.Serializer.JSON
        ],
        "Auth Adapters": [
          Pristine.Adapters.Auth.Bearer,
          Pristine.Adapters.Auth.APIKey,
          Pristine.Adapters.Auth.APIKeyAlias,
          Pristine.Adapters.Auth.OAuth2
        ],
        "Token Sources": [
          Pristine.Adapters.TokenSource.File,
          Pristine.Adapters.TokenSource.Static
        ],
        "Resilience Adapters": [
          Pristine.Adapters.Retry.Foundation,
          Pristine.Adapters.Retry.Noop,
          Pristine.Adapters.CircuitBreaker.Foundation,
          Pristine.Adapters.CircuitBreaker.Noop,
          Pristine.Adapters.RateLimit.BackoffWindow,
          Pristine.Adapters.RateLimit.Noop
        ],
        "Telemetry Adapters": [
          Pristine.Adapters.Telemetry.Foundation,
          Pristine.Adapters.Telemetry.Raw,
          Pristine.Adapters.Telemetry.Reporter,
          Pristine.Adapters.Telemetry.Noop
        ],
        "Other Adapters": [
          Pristine.Adapters.Compression.Gzip,
          Pristine.Adapters.Multipart.Ex,
          Pristine.Adapters.Tokenizer.Tiktoken,
          Pristine.Adapters.Streaming.SSE,
          Pristine.Adapters.Semaphore.Counting,
          Pristine.Adapters.BytesSemaphore.GenServer,
          Pristine.Adapters.Future.Polling,
          Pristine.Adapters.PoolManager
        ],
        Utilities: [
          Pristine.Core.Url,
          Pristine.Core.Headers,
          Pristine.Core.Auth,
          Pristine.Core.Querystring,
          Pristine.Core.Types,
          Pristine.Core.TelemetryHeaders,
          Pristine.PoolKey,
          Pristine.Error
        ]
      ]
    ]
  end

  defp package do
    [
      name: "pristine",
      description: description(),
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE assets guides),
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
      plt_add_apps: [:mix, :ex_unit, :oapi_generator],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end
end
