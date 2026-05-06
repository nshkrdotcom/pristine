defmodule Pristine.Workspace.DocsContractTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)
  @workspace_overview_path Path.expand("../../guides/workspace-overview.md", __DIR__)
  @architecture_path Path.expand("../../guides/architecture-and-package-boundaries.md", __DIR__)
  @testing_path Path.expand("../../guides/testing-and-verification.md", __DIR__)
  @examples_path Path.expand("../../examples/index.md", __DIR__)

  @public_docs [
    @readme_path,
    @workspace_overview_path,
    @architecture_path,
    @testing_path,
    @examples_path
  ]

  test "workspace docs explain the split monorepo shape" do
    readme = File.read!(@readme_path)
    workspace_overview = File.read!(@workspace_overview_path)
    architecture = File.read!(@architecture_path)
    testing = File.read!(@testing_path)
    examples = File.read!(@examples_path)

    assert readme =~ "`apps/pristine_runtime`"
    assert readme =~ "`apps/pristine_codegen`"
    assert readme =~ "`apps/pristine_provider_testkit`"
    assert readme =~ "mix monorepo.compile"
    assert readme =~ "mix mr.compile"
    assert readme =~ "mix quality"
    assert readme =~ "mix ci"
    assert readme =~ "mix blitz.workspace.impact <task>"
    assert readme =~ "apps/pristine_runtime/README.md"
    assert readme =~ "apps/pristine_codegen/README.md"

    assert workspace_overview =~ "`pristine`"
    assert workspace_overview =~ "`pristine_codegen`"
    assert workspace_overview =~ "`pristine_provider_testkit`"
    assert workspace_overview =~ "The root project is not the product runtime."

    assert architecture =~ "`apps/pristine_runtime`"
    assert architecture =~ "`apps/pristine_codegen`"
    assert architecture =~ "`apps/pristine_provider_testkit`"

    assert testing =~ "mix test"
    assert testing =~ "mix monorepo.format --check-formatted"
    assert testing =~ "mix mr.format --check-formatted"
    assert testing =~ "mix mr.dialyzer"
    assert testing =~ "PRISTINE_MONOREPO_MAX_CONCURRENCY"
    assert testing =~ "cd apps/pristine_runtime && mix test"
    assert testing =~ "cd apps/pristine_codegen && mix test"
    assert testing =~ "cd apps/pristine_provider_testkit && mix test"

    assert examples =~ "cd apps/pristine_runtime"
    assert examples =~ "mix run examples/demo.exs"
  end

  test "workspace docs do not describe the repo as a single published app" do
    violations =
      @public_docs
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        [
          "single Mix app",
          "mix pristine.generate",
          "mix pristine.validate",
          "lib/pristine.ex",
          "in-tree `monorepo.*` tasks"
        ]
        |> Enum.flat_map(fn marker ->
          if String.contains?(source, marker), do: ["#{path}: #{marker}"], else: []
        end)
      end)

    assert violations == []
  end
end
