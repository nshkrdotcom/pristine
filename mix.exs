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
      {:telemetry, "~> 1.4"},
      {:finch, "~> 0.21"},
      {:sinter, "~> 0.2.0"},
      {:foundation, "~> 0.2.1"},
      {:multipart_ex, "~> 0.1.0"},
      {:telemetry_reporter, "~> 0.1.0", optional: true, runtime: false},
      {:tiktoken_ex, "~> 0.2.0", optional: true, runtime: false},

      ### OpenAPI Generator
      {:oapi_generator,
       github: "nshkrdotcom/open-api-generator",
       branch: "doc-generator-fix",
       only: [:dev, :test],
       runtime: false},
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
    Shared runtime substrate and build-time bridge for first-party OpenAPI-based
    Elixir SDKs, including request execution, Foundation runtime wiring, and
    OAuth2 helpers.
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
        "guides/manual-contexts-and-adapters.md",
        "guides/oauth-and-token-sources.md",
        "guides/streaming-and-sse.md",
        "guides/code-generation.md",
        "guides/testing-and-verification.md"
      ],
      groups_for_extras: [
        Overview: [
          "README.md",
          "guides/getting-started.md"
        ],
        Runtime: [
          "guides/foundation-runtime.md",
          "guides/manual-contexts-and-adapters.md"
        ],
        "OAuth and Streaming": [
          "guides/oauth-and-token-sources.md",
          "guides/streaming-and-sse.md"
        ],
        "Build-Time": [
          "guides/code-generation.md"
        ],
        Development: [
          "guides/testing-and-verification.md"
        ],
        "Release Notes": [
          "CHANGELOG.md",
          "LICENSE"
        ]
      ],
      groups_for_modules: [
        "Public Runtime Boundary": [
          Pristine,
          Pristine.SDK.Context,
          Pristine.SDK.Response,
          Pristine.SDK.Error,
          Pristine.SDK.ResultClassification,
          Pristine.SDK.OpenAPI.Client,
          Pristine.SDK.OpenAPI.Operation,
          Pristine.SDK.OpenAPI.Runtime,
          Pristine.SDK.Profiles.Foundation,
          Pristine.SDK.OAuth2,
          Pristine.SDK.OAuth2.AuthorizationRequest,
          Pristine.SDK.OAuth2.Provider,
          Pristine.SDK.OAuth2.Token,
          Pristine.SDK.OAuth2.Error
        ],
        "Build-Time OpenAPI": [
          Pristine.OpenAPI.Bridge,
          Pristine.OpenAPI.Profile,
          Pristine.OpenAPI.Result
        ],
        "Runtime Internals": [
          Pristine.Profiles.Foundation,
          Pristine.Core.Pipeline,
          Pristine.Core.Context,
          Pristine.Core.EndpointMetadata,
          Pristine.Core.Request,
          Pristine.Core.Response,
          Pristine.Core.StreamResponse,
          Pristine.OpenAPI.Client,
          Pristine.OpenAPI.Operation,
          Pristine.OpenAPI.Runtime
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
          Pristine.OAuth2.SavedToken,
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
          Pristine.Ports.OAuthBackend,
          Pristine.Ports.OAuthBrowser,
          Pristine.Ports.OAuthCallbackListener,
          Pristine.Ports.Tokenizer,
          Pristine.Ports.Semaphore,
          Pristine.Ports.BytesSemaphore,
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
          Pristine.Adapters.Auth.ApiKey,
          Pristine.Adapters.Auth.OAuth2,
          Pristine.Adapters.OAuthBackend.Native,
          Pristine.Adapters.OAuthBrowser.SystemCmd,
          Pristine.Adapters.OAuthCallbackListener.Bandit
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
          Pristine.Adapters.Telemetry.Noop
        ],
        "Other Adapters": [
          Pristine.Adapters.Compression.Gzip,
          Pristine.Adapters.Multipart.Ex,
          Pristine.Adapters.Tokenizer.Tiktoken,
          Pristine.Adapters.Streaming.SSE,
          Pristine.Adapters.Semaphore.Counting,
          Pristine.Adapters.BytesSemaphore.GenServer,
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
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
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
