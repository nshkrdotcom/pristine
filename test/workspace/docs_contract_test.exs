defmodule Pristine.Workspace.DocsContractTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)
  @testing_path Path.expand("../../guides/testing-and-verification.md", __DIR__)
  @examples_path Path.expand("../../examples/index.md", __DIR__)

  test "workspace docs explain the split monorepo shape" do
    readme = File.read!(@readme_path)
    testing = File.read!(@testing_path)
    examples = File.read!(@examples_path)

    assert readme =~ "`apps/pristine_runtime`"
    assert readme =~ "`apps/pristine_codegen`"
    assert readme =~ "`apps/pristine_provider_testkit`"
    assert readme =~ "mix monorepo.compile"
    assert readme =~ "mix mr.compile"
    assert readme =~ "mix quality"
    assert readme =~ "mix ci"
    assert readme =~ "mix blitz.workspace <task>"
    assert readme =~ "apps/pristine_runtime/README.md"
    assert readme =~ "apps/pristine_codegen/README.md"

    assert testing =~ "mix monorepo.format --check-formatted"
    assert testing =~ "mix mr.format --check-formatted"
    assert testing =~ "mix mr.dialyzer"
    assert testing =~ "PRISTINE_MONOREPO_MAX_CONCURRENCY"
    assert testing =~ "`apps/pristine_runtime`"
    assert testing =~ "`apps/pristine_codegen`"

    assert examples =~ "cd apps/pristine_runtime"
    assert examples =~ "mix run examples/demo.exs"
  end

  test "workspace docs do not describe the repo as a single published app" do
    violations =
      [@readme_path, @testing_path, @examples_path]
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
