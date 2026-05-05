defmodule PristineCodegen.Render.ElixirSDKTest do
  use ExUnit.Case, async: true

  alias PristineCodegen.Compiler
  alias PristineCodegen.Render.ElixirSDK
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

    assert rendered_files["lib/widget_api/generated/runtime_schema.ex"] ==
             File.read!(Path.join(@golden_root, "generated/runtime_schema.ex"))

    assert rendered_files["lib/widget_api/generated/widgets.ex"] ==
             File.read!(Path.join(@golden_root, "generated/widgets.ex"))

    assert rendered_files["lib/widget_api/generated/schemas/types/widget.ex"] ==
             File.read!(Path.join(@golden_root, "generated/types/widget.ex"))

    assert rendered_files["lib/widget_api/generated/widgets.ex"] =~
             "WidgetAPI.Client.execute_generated_request(client, request)"

    assert rendered_files["lib/widget_api/generated/widgets.ex"] =~
             "OpenAPIClient.partition(params"

    assert rendered_files["lib/widget_api/generated/widgets.ex"] =~ "def stream_list_widgets("

    assert rendered_files["lib/widget_api/generated/widgets.ex"] =~
             "opts = normalize_request_opts!(opts)"

    assert rendered_files["lib/widget_api/generated/schemas/types/widget.ex"] =~
             "defstruct [:id, :name]"

    refute Enum.any?(Map.values(rendered_files), &String.contains?(&1, "Pristine.OpenAPI"))
    refute Enum.any?(Map.values(rendered_files), &String.contains?(&1, "Pristine.Runtime"))
    refute Enum.any?(Map.values(rendered_files), &String.contains?(&1, "GeneratedSupport"))
    refute Enum.any?(Map.values(rendered_files), &String.contains?(&1, "Pristine.Operation.new("))

    Enum.each(rendered_files, fn {relative_path, contents} ->
      Code.compile_string(contents, relative_path)
    end)
  end

  test "rejects binary auth override keys before rendering generated atoms" do
    project_root = tmp_project_root!("renderer-auth-key")

    assert {:ok, compilation} =
             Compiler.compile(SampleProvider, project_root: project_root)

    auth_policies =
      Enum.map(compilation.provider_ir.auth_policies, fn
        %{id: "session_basic"} = policy -> %{policy | override_source: %{key: "auth"}}
        policy -> policy
      end)

    provider_ir = %{compilation.provider_ir | auth_policies: auth_policies}

    error =
      assert_raise ArgumentError, fn ->
        ElixirSDK.render(provider_ir)
      end

    assert String.contains?(error.message, "source-owned atom")
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
