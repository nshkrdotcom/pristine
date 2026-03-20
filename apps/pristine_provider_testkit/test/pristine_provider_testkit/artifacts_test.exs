defmodule PristineProviderTestkit.ArtifactsTest do
  use ExUnit.Case, async: true

  alias PristineProviderTestkit.Artifacts

  test "returns only missing artifact paths" do
    existing = __ENV__.file
    missing = Path.join(System.tmp_dir!(), "pristine-provider-testkit-missing-artifact")

    assert Artifacts.missing_paths([existing, missing]) == [missing]
  end

  test "returns stale artifact paths when committed contents drift" do
    project_root =
      Path.join(
        System.tmp_dir!(),
        "pristine-provider-testkit-artifacts-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(project_root) end)
    File.rm_rf!(project_root)
    File.mkdir_p!(project_root)

    expected = [
      %{path: "priv/generated/provider_ir.json", contents: "{\"provider\":\"fresh\"}\n"},
      %{path: "lib/widget_api/generated/widgets.ex", contents: "defmodule Fresh do\nend\n"}
    ]

    Enum.each(expected, fn %{path: path, contents: contents} ->
      absolute_path = Path.join(project_root, path)
      File.mkdir_p!(Path.dirname(absolute_path))
      File.write!(absolute_path, contents)
    end)

    File.write!(
      Path.join(project_root, "priv/generated/provider_ir.json"),
      "{\"provider\":\"stale\"}\n"
    )

    assert Artifacts.stale_paths(expected, project_root) == ["priv/generated/provider_ir.json"]
  end
end
