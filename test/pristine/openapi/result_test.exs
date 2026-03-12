defmodule Pristine.OpenAPI.ResultTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.IR
  alias Pristine.OpenAPI.Result

  test "wraps generator state in a canonical result while preserving top-level compatibility" do
    result =
      Result.from_generator_state(generator_state_fixture(),
        source_contexts: source_contexts_fixture()
      )

    assert %Result{} = result
    assert result.files == generator_state_fixture().files
    assert result.operations == generator_state_fixture().operations
    assert result.schemas == generator_state_fixture().schemas
    assert %IR{} = result.ir

    assert %IR.SourceContext{title: "Widgets reference"} =
             result.source_contexts[{:get, "/widgets"}]

    assert [%{"path" => "/widgets"}] = result.docs_manifest["operations"]
    assert [%{"module" => "Widgets"}] = result.docs_manifest["modules"]
    assert [%{"type" => "t"}] = result.docs_manifest["schemas"]
  end

  defp generator_state_fixture do
    operation = operation_fixture()
    schema = schema_fixture()

    %{
      call: %{profile: :result_fixture},
      files: [
        %{
          module: Widgets,
          location: "lib/widgets.ex",
          contents: "defmodule Widgets do\nend\n",
          operations: [operation],
          schemas: []
        }
      ],
      operations: [operation],
      schemas: %{schema.ref => schema},
      spec: %{
        components: %{
          security_schemes: %{
            "bearerAuth" => %{"scheme" => "bearer", "type" => "http"}
          }
        }
      }
    }
  end

  defp operation_fixture do
    %{
      module_name: Widgets,
      function_name: :list_widgets,
      request_method: :get,
      request_path: "/widgets",
      summary: "List widgets",
      description: "Returns every widget.",
      deprecated: false,
      external_docs: %{description: "API docs", url: "https://example.com/widgets"},
      tags: ["Widgets"],
      security: [%{"bearerAuth" => []}],
      request_body_docs: nil,
      request_query_parameters: [
        %{
          name: "cursor",
          location: :query,
          description: "Pagination cursor",
          required: false,
          deprecated: false,
          example: "cursor-1",
          examples: %{},
          style: :form,
          explode: false,
          value_type: :string,
          extensions: %{}
        }
      ],
      request_path_parameters: [],
      request_header_parameters: [],
      response_docs: [
        %{status: 200, description: "Widget list", content_types: ["application/json"]}
      ],
      extensions: %{"x-pristine-beta" => true}
    }
  end

  defp schema_fixture do
    %{
      ref: {:ref, {"widgets.yaml", ["components", "schemas", "Widget"]}},
      module_name: Widget,
      type_name: :t,
      title: "Widget",
      description: "Widget schema.",
      deprecated: false,
      example: %{"name" => "Demo"},
      examples: [%{"name" => "Demo"}],
      external_docs: %{description: "Schema docs", url: "https://example.com/schema"},
      extensions: %{"x-pristine" => true},
      output_format: :struct,
      context: [{:response, Widgets, :list_widgets, 200, "application/json"}],
      fields: [
        %{
          name: "name",
          type: :string,
          description: "Widget name",
          default: "demo",
          required: true,
          nullable: false,
          deprecated: false,
          read_only: false,
          write_only: false,
          example: "Demo",
          examples: %{"default" => %{value: "Demo"}},
          external_docs: %{description: "Field docs", url: "https://example.com/widgets#name"},
          extensions: %{"x-extra" => "field"}
        }
      ]
    }
  end

  defp source_contexts_fixture do
    %{
      {:get, "/widgets"} => %{
        title: "Widgets reference",
        description: "Reference page for widgets.",
        url: "https://docs.example.com/widgets",
        code_samples: [
          %{
            language: "elixir",
            label: "Example",
            source: "Widgets.list_widgets(%{})"
          }
        ]
      }
    }
  end
end
