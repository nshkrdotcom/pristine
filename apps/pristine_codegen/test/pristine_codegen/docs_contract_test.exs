defmodule PristineCodegen.DocsContractTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)
  @guide_path Path.expand("../../guides/code-generation.md", __DIR__)

  @removed_contract_markers [
    "Pristine.OpenAPI.Bridge",
    "Pristine.OpenAPI.Profile",
    "Pristine.OpenAPI.Result",
    "Pristine.OpenAPI.IR",
    "Pristine.OpenAPI.Renderer",
    "Pristine.SDK",
    "GeneratedSupport",
    "priv/generated/manifest.json",
    "priv/generated/open_api_state.snapshot.term"
  ]

  test "codegen docs advertise the provider ir compiler contract" do
    readme = File.read!(@readme_path)
    guide = File.read!(@guide_path)

    assert readme =~ "`PristineCodegen.ProviderIR`"
    assert readme =~ "`PristineCodegen.Compiler`"
    assert readme =~ "`mix pristine.codegen.generate <ProviderModule>`"

    assert guide =~ "`PristineCodegen.Provider`"
    assert guide =~ "`PristineCodegen.ProviderIR`"
    assert guide =~ "`Pristine.execute/3`"
    assert guide =~ "`Pristine.stream/3`"
  end

  test "codegen docs do not advertise the removed bridge-centric contract" do
    violations =
      [@readme_path, @guide_path]
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        Enum.flat_map(@removed_contract_markers, fn marker ->
          if String.contains?(source, marker), do: ["#{path}: #{marker}"], else: []
        end)
      end)

    assert violations == []
  end
end
