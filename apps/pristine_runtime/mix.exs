if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule Pristine.Runtime.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/nshkrdotcom/pristine"

  def project do
    [
      app: :pristine,
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
      name: "Pristine",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :telemetry],
      mod: {Pristine.Application, []}
    ]
  end

  defp deps do
    [
      execution_plane_dep(),
      execution_plane_http_dep(),
      {:jason, "~> 1.4.5"},
      {:telemetry, "~> 1.4.2"},
      {:finch, "~> 0.23.0"},
      {:sinter, "~> 0.3.2"},
      {:foundation, "~> 0.2.1"},
      {:multipart_ex, "~> 0.1.0"},
      {:telemetry_reporter, "~> 0.1.0", optional: true, runtime: false},
      {:tiktoken_ex, "~> 0.2.0", optional: true, runtime: false},
      {:uuid, "~> 1.1.8"},
      {:mox, "~> 1.3.2", only: :test, runtime: false},
      {:plug, "~> 1.20.3", optional: true, runtime: false},
      {:plug_cowboy, "~> 2.9.0", only: [:dev, :test], runtime: false},
      {:bandit, "~> 1.12.5", optional: true, runtime: false},
      {:dialyxir, "~> 1.4.8", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false}
    ]
  end

  defp execution_plane_dep do
    workspace_dep({:execution_plane, "~> 0.3.0"})
  end

  defp execution_plane_http_dep do
    workspace_dep({:execution_plane_http, "~> 0.1.0"})
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end

  defp description do
    """
    Shared runtime substrate for first-party OpenAPI-based Elixir SDKs.
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
        "LICENSE.md",
        "guides/getting-started.md",
        "guides/foundation-runtime.md",
        "guides/manual-contexts-and-adapters.md",
        "guides/oauth-and-token-sources.md",
        "guides/streaming-and-sse.md"
      ],
      groups_for_extras: [
        Project: ["README.md", "CHANGELOG.md", "LICENSE.md"],
        Guides: [
          "guides/getting-started.md",
          "guides/foundation-runtime.md",
          "guides/manual-contexts-and-adapters.md",
          "guides/oauth-and-token-sources.md",
          "guides/streaming-and-sse.md"
        ]
      ]
    ]
  end

  defp package do
    [
      name: "pristine",
      description: description(),
      files: ~w(lib assets mix.exs README.md CHANGELOG.md LICENSE.md),
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
