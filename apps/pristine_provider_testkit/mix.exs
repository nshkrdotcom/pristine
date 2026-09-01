if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule Pristine.ProviderTestkit.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/pristine"

  def project do
    [
      app: :pristine_provider_testkit,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      build_path: "../../_build",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      test_ignore_filters: ["test/support/provider_fixture.exs"],
      deps: deps(),
      docs: docs(),
      description: description(),
      dialyzer: dialyzer(),
      name: "Pristine Provider Testkit",
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
      workspace_dep({:pristine_codegen, "~> 0.1.0"}),
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end

  defp description do
    """
    Shared verification helpers for generated provider SDK repositories.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "Pristine Provider Testkit",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      extras: ["README.md"],
      groups_for_extras: [
        Overview: ["README.md"]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "../../_build/plts/core"
    ]
  end
end
