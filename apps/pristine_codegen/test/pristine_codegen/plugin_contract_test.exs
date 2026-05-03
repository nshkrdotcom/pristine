defmodule PristineCodegen.PluginContractTest do
  use ExUnit.Case, async: true

  alias PristineCodegen.Compiler
  alias PristineCodegen.TestSupport.InvalidAuthProvider
  alias PristineCodegen.TestSupport.SampleProvider

  test "source plugins must return the bounded source dataset contract" do
    project_root = tmp_project_root!("source_contract")

    assert {:ok, compilation} =
             Compiler.compile(SampleProvider, project_root: project_root)

    assert Enum.map(compilation.provider_ir.operations, & &1.id) == [
             "sessions/create",
             "widgets/list"
           ]
  end

  test "auth plugins must return provider ir instead of provider-specific state" do
    project_root = tmp_project_root!("auth_contract")

    error =
      assert_raise ArgumentError, fn ->
        Compiler.compile(InvalidAuthProvider, project_root: project_root)
      end

    assert String.contains?(error.message, "expected auth plugin")
    assert String.contains?(error.message, "to return PristineCodegen.ProviderIR")
  end

  defp tmp_project_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "pristine-codegen-plugin-contract-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
