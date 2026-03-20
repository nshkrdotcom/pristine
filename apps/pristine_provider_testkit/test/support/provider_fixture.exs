defmodule PristineProviderTestkit.TestSupport.SampleProvider do
  @behaviour PristineCodegen.Provider

  @impl true
  def definition(_opts) do
    %{
      provider: %{
        id: :widget_api,
        base_module: WidgetAPI,
        package_app: :widget_api,
        package_name: "widget_api",
        source_strategy: :openapi_only
      },
      runtime_defaults: %{
        base_url: "https://api.example.com",
        default_headers: %{},
        user_agent_prefix: "WidgetAPI",
        timeout_ms: 10_000,
        retry_defaults: %{strategy: :standard},
        serializer: :json,
        typed_responses_default: true
      },
      operations: [
        %{
          id: "widgets/list",
          module: "Widgets",
          function: :list_widgets,
          method: :get,
          path_template: "/v1/widgets",
          summary: "List widgets",
          description: "Returns widgets.",
          path_params: [],
          query_params: [],
          header_params: [],
          body: %{mode: :none},
          form_data: %{mode: :none},
          request_schema: nil,
          response_schemas: %{200 => %{schema: "Widget", collection: true}},
          auth_policy_id: "default_bearer",
          pagination_policy_id: nil,
          runtime_metadata: %{
            resource: "widgets",
            retry_group: "widgets.read",
            circuit_breaker: "widget_api",
            rate_limit_group: "widget_api",
            telemetry_event: [:widget_api, :widgets, :list],
            timeout_ms: nil
          },
          docs_metadata: %{
            doc_url: "https://docs.example.com/widgets",
            examples: []
          }
        }
      ],
      schemas: [
        %{
          id: "Widget",
          module: "Types.Widget",
          kind: :object,
          fields: [
            %{name: "id", type: :string, required: true}
          ],
          source_refs: [
            %{path: "openapi/widgets.json", pointer: "#/components/schemas/Widget"}
          ]
        }
      ],
      auth_policies: [
        %{
          id: "default_bearer",
          mode: :use_client_default,
          security_schemes: ["bearerAuth"],
          override_source: nil,
          strategy_label: "Default bearer"
        }
      ],
      pagination_policies: [],
      docs_inventory: %{guides: [], examples: [], operations: %{}},
      fingerprints: %{
        sources: [
          %{path: "openapi/widgets.json", sha256: "widgets-openapi-sha", kind: :openapi}
        ],
        generation: %{compiler: "pristine_codegen", version: "0.1.0"}
      },
      artifact_plan: %{
        generated_code_dir: "lib/widget_api/generated",
        artifacts: [
          %{id: :provider_ir, path: "priv/generated/provider_ir.json"},
          %{id: :generation_manifest, path: "priv/generated/generation_manifest.json"},
          %{id: :docs_inventory, path: "priv/generated/docs_inventory.json"}
        ],
        forbidden_paths: [
          "priv/generated/manifest.json",
          "priv/generated/docs_manifest.json",
          "priv/generated/open_api_state.snapshot.term"
        ]
      }
    }
  end

  @impl true
  def paths(opts) do
    project_root = Keyword.fetch!(opts, :project_root)

    %{
      project_root: project_root,
      generated_code_dir: Path.join(project_root, "lib/widget_api/generated"),
      generated_artifact_dir: Path.join(project_root, "priv/generated")
    }
  end

  @impl true
  def source_plugins, do: []

  @impl true
  def auth_plugins, do: []

  @impl true
  def pagination_plugins, do: []

  @impl true
  def docs_plugins, do: []

  @impl true
  def refresh(_opts), do: :ok
end
