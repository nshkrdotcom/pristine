defmodule PristineCodegen.ProviderIRTest do
  use ExUnit.Case, async: true

  alias PristineCodegen.Compiler
  alias PristineCodegen.ProviderIR
  alias PristineCodegen.TestSupport.SampleProvider

  test "normalizes provider definitions plus bounded plugins into canonical provider ir" do
    project_root = tmp_project_root!("provider_ir")

    assert {:ok, compilation} =
             Compiler.compile(SampleProvider, project_root: project_root)

    assert %ProviderIR{} = provider_ir = compilation.provider_ir

    assert provider_ir.provider.id == :widget_api
    assert provider_ir.provider.base_module == WidgetAPI
    assert provider_ir.provider.package_app == :widget_api
    assert provider_ir.provider.package_name == "widget_api"
    assert provider_ir.provider.source_strategy == :openapi_plus_source_plugin

    assert provider_ir.runtime_defaults.base_url == "https://api.example.com"
    assert provider_ir.runtime_defaults.default_headers == %{"accept" => "application/json"}
    assert provider_ir.runtime_defaults.user_agent_prefix == "WidgetAPI"
    assert provider_ir.runtime_defaults.timeout_ms == 15_000
    assert provider_ir.runtime_defaults.typed_responses_default == true

    assert Enum.map(provider_ir.operations, & &1.id) == ["sessions/create", "widgets/list"]
    assert Enum.map(provider_ir.schemas, & &1.id) == ["SessionToken", "Widget"]
    assert Enum.map(provider_ir.auth_policies, & &1.id) == ["default_bearer", "session_basic"]
    assert Enum.map(provider_ir.pagination_policies, & &1.id) == ["widgets_cursor"]

    assert Enum.find(provider_ir.operations, &(&1.id == "widgets/list")).auth_policy_id ==
             "default_bearer"

    assert Enum.find(provider_ir.operations, &(&1.id == "widgets/list")).pagination_policy_id ==
             "widgets_cursor"

    assert Enum.find(provider_ir.operations, &(&1.id == "widgets/list")).header_params == [
             %{
               key: :request_id,
               name: "x-request-id",
               required: false
             }
           ]

    assert get_in(provider_ir.docs_inventory.operations, ["widgets/list", :doc_url]) ==
             "https://docs.example.com/widgets"

    assert provider_ir.fingerprints.sources == [
             %{kind: :docs, path: "docs/sessions.md", sha256: "sessions-doc-sha"},
             %{kind: :openapi, path: "openapi/widgets.json", sha256: "widgets-openapi-sha"}
           ]

    assert Enum.map(provider_ir.artifact_plan.artifacts, & &1.path) == [
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

    assert provider_ir.artifact_plan.forbidden_paths == [
             "priv/generated/manifest.json",
             "priv/generated/docs_manifest.json",
             "priv/generated/open_api_state.snapshot.term"
           ]
  end

  test "renders provider ir into a stable json-friendly map" do
    project_root = tmp_project_root!("provider_ir_json")

    assert {:ok, compilation} =
             Compiler.compile(SampleProvider, project_root: project_root)

    provider_ir = ProviderIR.to_map(compilation.provider_ir)

    assert get_in(provider_ir, ["provider", "id"]) == "widget_api"

    assert get_in(provider_ir, ["operations", Access.at(0), "module"]) ==
             "WidgetAPI.Generated.Sessions"

    assert get_in(provider_ir, ["schemas", Access.at(1), "module"]) ==
             "WidgetAPI.Generated.Types.Widget"

    assert Jason.decode!(Jason.encode!(provider_ir)) == provider_ir
  end

  defp tmp_project_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "pristine-codegen-provider-ir-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
