defmodule PristineCodegen.ArtifactsTest do
  use ExUnit.Case, async: true

  alias PristineCodegen.Compiler
  alias PristineCodegen.TestSupport.SampleProvider

  test "writes the final committed artifact contract and no legacy artifacts" do
    project_root = tmp_project_root!("artifacts")

    assert {:ok, compilation} =
             Compiler.generate(SampleProvider, project_root: project_root)

    assert Enum.map(compilation.provider_ir.artifact_plan.artifacts, & &1.path) == [
             "lib/widget_api/generated/client.ex",
             "lib/widget_api/generated/sessions.ex",
             "lib/widget_api/generated/types/session_token.ex",
             "lib/widget_api/generated/types/widget.ex",
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
