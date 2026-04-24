defmodule Pristine.Runtime.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/nshkrdotcom/pristine"
  @execution_plane_version "~> 0.1.0"

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
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.4"},
      {:finch, "~> 0.21"},
      {:sinter, "~> 0.3.1"},
      {:foundation, "~> 0.2.1"},
      {:multipart_ex, "~> 0.1.0"},
      {:telemetry_reporter, "~> 0.1.0", optional: true, runtime: false},
      {:tiktoken_ex, "~> 0.2.0", optional: true, runtime: false},
      {:uuid, "~> 1.1"},
      {:mox, "~> 1.2", only: :test, runtime: false},
      {:plug, "~> 1.19", optional: true, runtime: false},
      {:plug_cowboy, "~> 2.8", only: [:dev, :test], runtime: false},
      {:bandit, "~> 1.10", optional: true, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp execution_plane_dep do
    case workspace_dep_path("../../../execution_plane", "PRISTINE_HEX_DEPS") do
      nil -> {:execution_plane, @execution_plane_version}
      path -> {:execution_plane, path: path}
    end
  end

  defp workspace_dep_path(relative_path, force_hex_env) do
    if prefer_workspace_paths?(force_hex_env) do
      path = Path.expand(relative_path, __DIR__)
      if File.dir?(path), do: path
    end
  end

  defp prefer_workspace_paths?(force_hex_env) do
    workspace_paths_forced?(force_hex_env) or
      (not release_deps_forced?(force_hex_env) and not Enum.member?(Path.split(__DIR__), "deps"))
  end

  defp release_deps_forced?(force_hex_env) do
    force_hex_deps?(force_hex_env) or
      Enum.any?(System.argv(), &(&1 in ["hex.build", "hex.publish"]))
  end

  defp workspace_paths_forced?(force_hex_env) do
    not force_hex_deps?(force_hex_env) and
      System.get_env("FORCE_WORKSPACE_PATH_DEPS") in ["1", "true", "TRUE", "yes", "YES"]
  end

  defp force_hex_deps?(force_hex_env) do
    System.get_env(force_hex_env) in ["1", "true", "TRUE", "yes", "YES"]
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
