defmodule PristineProviderTestkit.ConformanceTest do
  use ExUnit.Case, async: true

  alias PristineProviderTestkit.Conformance

  test "verifies committed generated artifacts against the shared compiler contract" do
    project_root = tmp_project_root!("conformance")

    assert :ok =
             Conformance.verify_provider(PristineProviderTestkit.TestSupport.SampleProvider,
               project_root: project_root,
               write?: true
             )

    assert :ok =
             Conformance.verify_provider(PristineProviderTestkit.TestSupport.SampleProvider,
               project_root: project_root
             )

    File.write!(Path.join(project_root, "priv/generated/provider_ir.json"), "{\"drift\":true}\n")

    assert {:error, failures} =
             Conformance.verify_provider(
               PristineProviderTestkit.TestSupport.SampleProvider,
               project_root: project_root
             )

    assert "priv/generated/provider_ir.json" in failures.stale_paths
  end

  defp tmp_project_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "pristine-provider-testkit-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
