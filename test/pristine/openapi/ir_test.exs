defmodule Pristine.OpenAPI.IRTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.IR
  alias Pristine.OpenAPI.Mapper

  test "maps generator state into canonical IR structs" do
    ir =
      Mapper.to_ir(generator_state_fixture(),
        source_contexts: source_contexts_fixture()
      )

    assert %IR{} = ir

    assert [%IR.Operation{} = operation] = ir.operations
    assert operation.method == :get
    assert operation.path == "/widgets"
    assert operation.source_context.title == "Widgets reference"
    assert [%IR.CodeSample{language: "elixir"}] = operation.code_samples

    assert [%IR.Schema{} = schema] = ir.schemas
    assert schema.title == "Widget"
    assert [%IR.Field{name: "name", description: "Widget name"}] = schema.fields

    assert %IR.SecurityScheme{name: "bearerAuth", type: "http", scheme: "bearer"} =
             ir.security_schemes["bearerAuth"]
  end

  defp generator_state_fixture do
    operation = %{
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
      request_query_parameters: [],
      request_path_parameters: [],
      request_header_parameters: [],
      response_docs: [
        %{status: 200, description: "Widget list", content_types: ["application/json"]}
      ],
      extensions: %{"x-pristine-beta" => true}
    }

    schema = %{
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

    %{
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

  defp source_contexts_fixture do
    %{
      {:get, "/widgets"} => %{
        title: "Widgets reference",
        summary: "Reference summary",
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
