defmodule PristineCodegen.Render.ElixirSDKTest do
  use ExUnit.Case, async: true

  alias PristineCodegen.Compiler
  alias PristineCodegen.TestSupport.SampleProvider

  @golden_root Path.expand("../../fixtures/golden/widget_api", __DIR__)

  test "renders client, operation, pagination, and type modules from provider ir" do
    project_root = tmp_project_root!("renderer")

    assert {:ok, compilation} =
             Compiler.compile(SampleProvider, project_root: project_root)

    rendered_files =
      compilation.rendered_files
      |> Enum.map(&{&1.relative_path, &1.contents})
      |> Map.new()

    assert rendered_files["lib/widget_api/generated/client.ex"] ==
             File.read!(Path.join(@golden_root, "generated/client.ex"))

    assert rendered_files["lib/widget_api/generated/widgets.ex"] ==
             File.read!(Path.join(@golden_root, "generated/widgets.ex"))

    assert rendered_files["lib/widget_api/generated/types/widget.ex"] ==
             File.read!(Path.join(@golden_root, "generated/types/widget.ex"))

    assert rendered_files["lib/widget_api/generated/widgets.ex"] =~
             "Pristine.execute(client, operation, opts)"

    assert rendered_files["lib/widget_api/generated/widgets.ex"] =~
             "Pristine.Operation.partition(params"

    assert rendered_files["lib/widget_api/generated/widgets.ex"] =~ "def stream_list_widgets("
    assert rendered_files["lib/widget_api/generated/types/widget.ex"] =~ "defstruct [:id, :name]"

    refute Enum.any?(Map.values(rendered_files), &String.contains?(&1, "Pristine.OpenAPI"))
    refute Enum.any?(Map.values(rendered_files), &String.contains?(&1, "Pristine.SDK"))
    refute Enum.any?(Map.values(rendered_files), &String.contains?(&1, "GeneratedSupport"))

    Enum.each(rendered_files, fn {relative_path, contents} ->
      Code.compile_string(contents, relative_path)
    end)
  end

  defp tmp_project_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "pristine-codegen-renderer-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
