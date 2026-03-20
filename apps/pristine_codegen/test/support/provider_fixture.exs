defmodule PristineCodegen.TestSupport.SampleProvider do
  @behaviour PristineCodegen.Provider

  @base_module WidgetAPI
  @generated_code_dir "lib/widget_api/generated"
  @generated_artifact_dir "priv/generated"
  @legacy_artifacts [
    "priv/generated/manifest.json",
    "priv/generated/docs_manifest.json",
    "priv/generated/open_api_state.snapshot.term"
  ]

  @impl true
  def definition(_opts) do
    %{
      provider: %{
        id: :widget_api,
        base_module: @base_module,
        package_app: :widget_api,
        package_name: "widget_api",
        source_strategy: :openapi_plus_source_plugin
      },
      runtime_defaults: %{
        base_url: "https://api.example.com",
        default_headers: %{"accept" => "application/json"},
        user_agent_prefix: "WidgetAPI",
        timeout_ms: 15_000,
        retry_defaults: %{strategy: :standard, max_attempts: 3},
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
          description: "Returns widgets in cursor order.",
          path_params: [],
          query_params: [
            %{name: "cursor", key: :cursor, required: false},
            %{name: "limit", key: :limit, required: false}
          ],
          header_params: [
            %{name: "x-request-id", key: :request_id, required: false}
          ],
          body: %{mode: :none},
          form_data: %{mode: :none},
          request_schema: nil,
          response_schemas: %{
            200 => %{schema: "Widget", collection: true}
          },
          auth_policy_id: nil,
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
            examples: [],
            source: %{kind: :openapi, path: "openapi/widgets.json"}
          }
        }
      ],
      schemas: [
        %{
          id: "Widget",
          module: "Types.Widget",
          kind: :object,
          fields: [
            %{name: "id", type: :string, required: true},
            %{name: "name", type: :string, required: true}
          ],
          source_refs: [
            %{path: "openapi/widgets.json", pointer: "#/components/schemas/Widget"}
          ]
        }
      ],
      auth_policies: [],
      pagination_policies: [],
      docs_inventory: %{
        guides: [],
        examples: [],
        operations: %{}
      },
      fingerprints: %{
        sources: [
          %{path: "openapi/widgets.json", sha256: "widgets-openapi-sha", kind: :openapi}
        ],
        generation: %{compiler: "pristine_codegen", version: "0.1.0"}
      },
      artifact_plan: %{
        generated_code_dir: @generated_code_dir,
        artifacts: [
          %{id: :provider_ir, path: Path.join(@generated_artifact_dir, "provider_ir.json")},
          %{
            id: :generation_manifest,
            path: Path.join(@generated_artifact_dir, "generation_manifest.json")
          },
          %{id: :docs_inventory, path: Path.join(@generated_artifact_dir, "docs_inventory.json")},
          %{
            id: :source_inventory,
            path: Path.join(@generated_artifact_dir, "source_inventory.json")
          },
          %{
            id: :operation_auth_policies,
            path: Path.join(@generated_artifact_dir, "operation_auth_policies.json")
          }
        ],
        forbidden_paths: @legacy_artifacts
      }
    }
  end

  @impl true
  def paths(opts) do
    project_root = Keyword.fetch!(opts, :project_root)

    %{
      project_root: project_root,
      generated_code_dir: Path.join(project_root, @generated_code_dir),
      generated_artifact_dir: Path.join(project_root, @generated_artifact_dir)
    }
  end

  @impl true
  def source_plugins do
    [PristineCodegen.TestSupport.SampleProvider.SourcePlugin]
  end

  @impl true
  def auth_plugins do
    [PristineCodegen.TestSupport.SampleProvider.AuthPlugin]
  end

  @impl true
  def pagination_plugins do
    [PristineCodegen.TestSupport.SampleProvider.PaginationPlugin]
  end

  @impl true
  def docs_plugins do
    [PristineCodegen.TestSupport.SampleProvider.DocsPlugin]
  end

  @impl true
  def refresh(opts) do
    project_root = Keyword.fetch!(opts, :project_root)
    refresh_marker = Path.join(project_root, "priv/upstream/refreshed.txt")
    File.mkdir_p!(Path.dirname(refresh_marker))
    File.write!(refresh_marker, "sample refresh\n")
    :ok
  end
end

defmodule PristineCodegen.TestSupport.SampleProvider.SourcePlugin do
  @behaviour PristineCodegen.Plugin.Source

  @impl true
  def load(_provider, _opts) do
    %PristineCodegen.Source.Dataset{
      operations: [
        %{
          id: "sessions/create",
          module: "Sessions",
          function: :create_session,
          method: :post,
          path_template: "/v1/sessions",
          summary: "Create a session",
          description: "Creates a short-lived API session token.",
          path_params: [],
          query_params: [],
          header_params: [],
          body: %{mode: :key, key: :payload},
          form_data: %{mode: :none},
          request_schema: "SessionRequest",
          response_schemas: %{
            201 => %{schema: "SessionToken", collection: false}
          },
          auth_policy_id: nil,
          pagination_policy_id: nil,
          runtime_metadata: %{
            resource: "sessions",
            retry_group: "sessions.write",
            circuit_breaker: "widget_api",
            rate_limit_group: "widget_api",
            telemetry_event: [:widget_api, :sessions, :create],
            timeout_ms: 20_000
          },
          docs_metadata: %{
            doc_url: "https://docs.example.com/sessions",
            examples: [],
            source: %{kind: :docs, path: "docs/sessions.md"}
          }
        }
      ],
      schemas: [
        %{
          id: "SessionToken",
          module: "Types.SessionToken",
          kind: :object,
          fields: [
            %{name: "token", type: :string, required: true}
          ],
          source_refs: [
            %{path: "docs/sessions.md", pointer: "#session-token"}
          ]
        }
      ],
      fingerprints: %{
        sources: [
          %{path: "docs/sessions.md", sha256: "sessions-doc-sha", kind: :docs}
        ]
      }
    }
  end
end

defmodule PristineCodegen.TestSupport.SampleProvider.AuthPlugin do
  @behaviour PristineCodegen.Plugin.Auth

  @impl true
  def transform(provider_ir, _opts) do
    auth_policies = [
      %PristineCodegen.ProviderIR.AuthPolicy{
        id: "default_bearer",
        mode: :use_client_default,
        security_schemes: ["bearerAuth"],
        override_source: nil,
        strategy_label: "Default bearer token"
      },
      %PristineCodegen.ProviderIR.AuthPolicy{
        id: "session_basic",
        mode: :request_override,
        security_schemes: ["basicAuth"],
        override_source: %{key: "auth"},
        strategy_label: "Per-request session client credentials"
      }
    ]

    operations =
      Enum.map(provider_ir.operations, fn operation ->
        auth_policy_id =
          case operation.id do
            "widgets/list" -> "default_bearer"
            "sessions/create" -> "session_basic"
          end

        %{operation | auth_policy_id: auth_policy_id}
      end)

    %{provider_ir | auth_policies: auth_policies, operations: operations}
  end
end

defmodule PristineCodegen.TestSupport.SampleProvider.PaginationPlugin do
  @behaviour PristineCodegen.Plugin.Pagination

  @impl true
  def transform(provider_ir, _opts) do
    pagination_policies = [
      %PristineCodegen.ProviderIR.PaginationPolicy{
        id: "widgets_cursor",
        strategy: :cursor,
        request_mapping: %{cursor_param: "cursor", limit_param: "limit"},
        response_mapping: %{cursor_path: ["next_cursor"]},
        default_limit: 100,
        items_path: ["results"]
      }
    ]

    operations =
      Enum.map(provider_ir.operations, fn
        %{id: "widgets/list"} = operation ->
          %{operation | pagination_policy_id: "widgets_cursor"}

        operation ->
          operation
      end)

    %{provider_ir | pagination_policies: pagination_policies, operations: operations}
  end
end

defmodule PristineCodegen.TestSupport.SampleProvider.DocsPlugin do
  @behaviour PristineCodegen.Plugin.Docs

  @impl true
  def transform(provider_ir, _opts) do
    docs_inventory = %PristineCodegen.ProviderIR.DocsInventory{
      guides: [
        %{
          id: "widget-api-overview",
          title: "Widget API Overview",
          path: "guides/widget-api-overview.md"
        }
      ],
      examples: [
        %{
          id: "widgets.list.default",
          operation_id: "widgets/list",
          summary: "List widgets"
        }
      ],
      operations: %{
        "widgets/list" => %{
          doc_url: "https://docs.example.com/widgets",
          examples: [
            %{
              label: "Default list request",
              params: %{"limit" => 10, "x-request-id" => "req-1"}
            }
          ]
        },
        "sessions/create" => %{
          doc_url: "https://docs.example.com/sessions",
          examples: [
            %{
              label: "Create a session",
              params: %{"payload" => %{"name" => "Ada"}}
            }
          ]
        }
      }
    }

    operations =
      Enum.map(provider_ir.operations, fn operation ->
        docs_metadata =
          Map.merge(
            operation.docs_metadata,
            Map.get(docs_inventory.operations, operation.id, %{})
          )

        %{operation | docs_metadata: docs_metadata}
      end)

    %{provider_ir | docs_inventory: docs_inventory, operations: operations}
  end
end

defmodule PristineCodegen.TestSupport.InvalidAuthProvider do
  @behaviour PristineCodegen.Provider

  alias PristineCodegen.TestSupport.InvalidAuthPlugin
  alias PristineCodegen.TestSupport.SampleProvider

  @impl true
  def definition(opts), do: SampleProvider.definition(opts)

  @impl true
  def paths(opts), do: SampleProvider.paths(opts)

  @impl true
  def source_plugins, do: []

  @impl true
  def auth_plugins, do: [InvalidAuthPlugin]

  @impl true
  def pagination_plugins, do: []

  @impl true
  def docs_plugins, do: []

  @impl true
  def refresh(_opts), do: :ok
end

defmodule PristineCodegen.TestSupport.InvalidAuthPlugin do
  @behaviour PristineCodegen.Plugin.Auth

  @impl true
  def transform(_provider_ir, _opts) do
    %{unexpected: :provider_specific_state}
  end
end
