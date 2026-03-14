defmodule Pristine.DocsContractTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)
  @getting_started_path Path.expand("../../guides/getting-started.md", __DIR__)
  @code_generation_path Path.expand("../../guides/code-generation.md", __DIR__)

  @public_docs [
    @readme_path,
    @getting_started_path,
    @code_generation_path
  ]

  @removed_contract_markers [
    "mix pristine.generate",
    "mix pristine.validate",
    "mix pristine.docs",
    "mix pristine.openapi",
    "Pristine.load_manifest",
    "Pristine.load_manifest_file",
    "Pristine.execute(",
    "Pristine.execute_endpoint(",
    "Pristine.Runtime",
    "Pristine.Manifest",
    "Pristine.Codegen",
    "Pristine.Docs"
  ]

  @deleted_guides [
    Path.expand("../../guides/architecture.md", __DIR__),
    Path.expand("../../guides/manifests.md", __DIR__),
    Path.expand("../../guides/ports-and-adapters.md", __DIR__),
    Path.expand("../../guides/pipeline.md", __DIR__),
    Path.expand("../../guides/streaming.md", __DIR__)
  ]

  test "public docs advertise the retained runtime boundary and build-time seam" do
    readme = File.read!(@readme_path)
    getting_started = File.read!(@getting_started_path)
    code_generation = File.read!(@code_generation_path)

    assert readme =~ "`Pristine.execute_request/3`"
    assert readme =~ "`Pristine.foundation_context/1`"
    assert readme =~ "`Pristine.SDK.*`"

    assert getting_started =~ "`Pristine.execute_request/3`"
    assert getting_started =~ "`Pristine.foundation_context/1`"

    assert code_generation =~ "`Pristine.OpenAPI.Bridge.run/3`"
    assert code_generation =~ "It is not the normal consumer runtime entry"
  end

  test "public docs do not advertise the removed manifest-first surface" do
    violations =
      Enum.flat_map(@public_docs, fn path ->
        source = File.read!(path)

        Enum.flat_map(@removed_contract_markers, fn marker ->
          if String.contains?(source, marker) do
            ["#{path}: #{marker}"]
          else
            []
          end
        end)
      end)

    assert violations == []
  end

  test "deleted manifest-first guides are gone" do
    assert Enum.filter(@deleted_guides, &File.exists?/1) == []
  end
end
