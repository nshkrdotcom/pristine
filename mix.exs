defmodule Pristine.Workspace.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/pristine"

  def project do
    [
      app: :pristine_workspace,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      blitz_workspace: blitz_workspace(),
      docs: docs(),
      description: description(),
      dialyzer: dialyzer(),
      name: "Pristine Workspace",
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
      {:pristine, path: "apps/pristine_runtime"},
      {:pristine_codegen, path: "apps/pristine_codegen"},
      {:pristine_provider_testkit, path: "apps/pristine_provider_testkit"},
      {:plug, "~> 1.19", only: [:dev, :test], runtime: false},
      {:bandit, "~> 1.10", only: [:dev, :test], runtime: false},
      {:telemetry_reporter, "~> 0.1.0", only: [:dev, :test], runtime: false},
      {:tiktoken_ex, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    mr_aliases =
      ~w[deps.get format compile test credo dialyzer docs]
      |> Enum.map(fn task -> {:"mr.#{task}", ["monorepo.#{task}"]} end)

    [
      ci: [
        "monorepo.format --check-formatted",
        "monorepo.compile",
        "monorepo.test",
        "monorepo.credo --strict",
        "monorepo.dialyzer",
        "monorepo.docs"
      ]
    ] ++ mr_aliases
  end

  defp description do
    """
    Tooling root for the Pristine non-umbrella monorepo.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "Pristine Workspace",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      extras: [
        "README.md",
        "guides/testing-and-verification.md",
        "examples/index.md"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_deps: :app_tree,
      plt_add_apps: [:mix, :plug, :bandit, :telemetry_reporter, :tiktoken_ex],
      plt_core_path: "_build/plts/core"
    ]
  end

  defp blitz_workspace do
    [
      root: __DIR__,
      projects: [".", "apps/*"],
      isolation: [
        deps_path: true,
        build_path: true,
        lockfile: true,
        hex_home: "_build/hex",
        unset_env: ["HEX_API_KEY"]
      ],
      parallelism: [
        env: "PRISTINE_MONOREPO_MAX_CONCURRENCY",
        multiplier: :auto,
        base: [
          deps_get: 3,
          format: 4,
          compile: 2,
          test: 2,
          credo: 2,
          dialyzer: 1,
          docs: 1
        ],
        overrides: []
      ],
      tasks: [
        deps_get: [args: ["deps.get"], preflight?: false],
        format: [args: ["format"]],
        compile: [args: ["compile", "--warnings-as-errors"]],
        test: [args: ["test"], mix_env: "test", color: true],
        credo: [args: ["credo"]],
        dialyzer: [args: ["dialyzer", "--force-check"]],
        docs: [args: ["docs"]]
      ]
    ]
  end
end
