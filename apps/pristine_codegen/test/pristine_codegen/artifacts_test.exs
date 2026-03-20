defmodule PristineCodegen.ArtifactsTest do
  use ExUnit.Case, async: true

  alias PristineCodegen.Compiler
  alias PristineCodegen.TestSupport.CustomArtifactProvider
  alias PristineCodegen.TestSupport.SampleProvider

  test "writes the final committed artifact contract and no legacy artifacts" do
    project_root = tmp_project_root!("artifacts")

    assert {:ok, compilation} =
             Compiler.generate(SampleProvider, project_root: project_root)

    assert Enum.map(compilation.provider_ir.artifact_plan.artifacts, & &1.path) == [
             "lib/widget_api/generated/client.ex",
             "lib/widget_api/generated/runtime_schema.ex",
             "lib/widget_api/generated/schemas/types/session_token.ex",
             "lib/widget_api/generated/schemas/types/widget.ex",
             "lib/widget_api/generated/sessions.ex",
             "lib/widget_api/generated/widgets.ex",
             "priv/generated/provider_ir.json",
             "priv/generated/generation_manifest.json",
             "priv/generated/docs_inventory.json",
             "priv/generated/source_inventory.json",
             "priv/generated/operation_auth_policies.json"
           ]

    assert File.exists?(Path.join(project_root, "priv/generated/provider_ir.json"))
    assert File.exists?(Path.join(project_root, "priv/generated/generation_manifest.json"))
    assert File.exists?(Path.join(project_root, "priv/generated/docs_inventory.json"))
    assert File.exists?(Path.join(project_root, "priv/generated/source_inventory.json"))
    assert File.exists?(Path.join(project_root, "priv/generated/operation_auth_policies.json"))

    refute File.exists?(Path.join(project_root, "priv/generated/manifest.json"))
    refute File.exists?(Path.join(project_root, "priv/generated/docs_manifest.json"))
    refute File.exists?(Path.join(project_root, "priv/generated/open_api_state.snapshot.term"))

    provider_ir =
      project_root
      |> Path.join("priv/generated/provider_ir.json")
      |> File.read!()
      |> Jason.decode!()

    generation_manifest =
      project_root
      |> Path.join("priv/generated/generation_manifest.json")
      |> File.read!()
      |> Jason.decode!()

    docs_inventory =
      project_root
      |> Path.join("priv/generated/docs_inventory.json")
      |> File.read!()
      |> Jason.decode!()

    source_inventory =
      project_root
      |> Path.join("priv/generated/source_inventory.json")
      |> File.read!()
      |> Jason.decode!()

    auth_inventory =
      project_root
      |> Path.join("priv/generated/operation_auth_policies.json")
      |> File.read!()
      |> Jason.decode!()

    assert get_in(provider_ir, ["provider", "id"]) == "widget_api"
    assert generation_manifest["operation_count"] == 2

    assert docs_inventory["operations"]["widgets/list"]["doc_url"] ==
             "https://docs.example.com/widgets"

    assert Enum.map(source_inventory["sources"], & &1["path"]) == [
             "docs/sessions.md",
             "openapi/widgets.json"
           ]

    assert auth_inventory["sessions/create"] == "session_basic"
  end

  test "writes and verifies against provider output path overrides" do
    project_root = tmp_project_root!("override-root")
    generated_code_dir = Path.join(project_root, "tmp/generated/code")
    generated_artifact_dir = Path.join(project_root, "tmp/generated/artifacts")

    assert {:ok, _compilation} =
             Compiler.generate(
               SampleProvider,
               project_root: project_root,
               generated_code_dir: generated_code_dir,
               generated_artifact_dir: generated_artifact_dir
             )

    assert File.exists?(Path.join(generated_code_dir, "client.ex"))
    assert File.exists?(Path.join(generated_code_dir, "widgets.ex"))
    assert File.exists?(Path.join(generated_artifact_dir, "provider_ir.json"))
    assert File.exists?(Path.join(generated_artifact_dir, "generation_manifest.json"))

    refute File.exists?(Path.join(project_root, "lib/widget_api/generated/client.ex"))
    refute File.exists?(Path.join(project_root, "priv/generated/provider_ir.json"))

    assert :ok =
             Compiler.verify(
               SampleProvider,
               project_root: project_root,
               generated_code_dir: generated_code_dir,
               generated_artifact_dir: generated_artifact_dir
             )
  end

  test "renders provider-specific artifacts through the shared compiler contract" do
    project_root = tmp_project_root!("custom-artifacts")

    assert {:ok, compilation} =
             Compiler.generate(CustomArtifactProvider, project_root: project_root)

    assert "priv/generated/custom_summary.json" in Enum.map(
             compilation.provider_ir.artifact_plan.artifacts,
             & &1.path
           )

    custom_summary =
      project_root
      |> Path.join("priv/generated/custom_summary.json")
      |> File.read!()
      |> Jason.decode!()

    assert custom_summary["generated_file_count"] == length(compilation.rendered_files)
    assert custom_summary["operation_ids"] == ["sessions/create", "widgets/list"]

    assert :ok = Compiler.verify(CustomArtifactProvider, project_root: project_root)
  end

  defp tmp_project_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "pristine-codegen-artifacts-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
