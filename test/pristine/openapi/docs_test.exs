defmodule Pristine.OpenAPI.DocsTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.DocComposer
  alias Pristine.OpenAPI.Docs
  alias Pristine.OpenAPI.Mapper

  test "builds docs manifest entries from the shared composer rules" do
    generator_state = generator_state_fixture()
    ir = Mapper.to_ir(generator_state, source_contexts: source_contexts_fixture())
    manifest = Docs.build(generator_state, ir)

    [operation_entry] = manifest["operations"]
    [module_entry] = manifest["modules"]
    [schema_entry] = manifest["schemas"]
    [source_context_entry] = manifest["source_contexts"]

    assert operation_entry["doc"] ==
             DocComposer.operation_doc(hd(ir.operations),
               source_context: hd(ir.operations).source_context
             )

    assert module_entry["doc"] ==
             DocComposer.module_doc(hd(generator_state.files),
               source_contexts: ir.source_contexts
             )

    assert schema_entry["doc"] == DocComposer.schema(hd(ir.schemas)).doc

    assert MapSet.new(Map.keys(hd(schema_entry["fields"]))) ==
             MapSet.new([
               "default",
               "description",
               "deprecated",
               "example",
               "examples",
               "external_docs",
               "extensions",
               "name",
               "nullable",
               "read_only",
               "required",
               "type",
               "write_only"
             ])

    assert source_context_entry["title"] == "Widgets reference"
    assert operation_entry["doc"] =~ "## Source Context"
    assert module_entry["doc"] =~ "## Operations"
  end

  test "assigns unique stable labels to anonymous schemas with different field shapes" do
    ref_a = make_ref()
    ref_b = make_ref()

    schema_a = %Pristine.OpenAPI.IR.Schema{
      ref: ref_a,
      module_name: nil,
      type_name: :map,
      title: nil,
      description: nil,
      deprecated: false,
      example: nil,
      examples: nil,
      external_docs: nil,
      extensions: %{},
      output_format: :typed_map,
      contexts: [{:field, ref_a, "and"}],
      fields: [
        %Pristine.OpenAPI.IR.Field{
          name: "and",
          type: :string,
          description: nil,
          default: nil,
          required: true,
          nullable: false,
          deprecated: false,
          read_only: false,
          write_only: false,
          example: nil,
          examples: nil,
          external_docs: nil,
          extensions: %{}
        }
      ]
    }

    schema_b = %Pristine.OpenAPI.IR.Schema{
      ref: ref_b,
      module_name: nil,
      type_name: :map,
      title: nil,
      description: nil,
      deprecated: false,
      example: nil,
      examples: nil,
      external_docs: nil,
      extensions: %{},
      output_format: :typed_map,
      contexts: [{:field, ref_b, "or"}],
      fields: [
        %Pristine.OpenAPI.IR.Field{
          name: "or",
          type: :string,
          description: nil,
          default: nil,
          required: true,
          nullable: false,
          deprecated: false,
          read_only: false,
          write_only: false,
          example: nil,
          examples: nil,
          external_docs: nil,
          extensions: %{}
        }
      ]
    }

    manifest =
      Docs.build(
        %{call: %{profile: :docs_fixture}, files: [], operations: [], schemas: %{}, spec: %{}},
        %Pristine.OpenAPI.IR{
          operations: [],
          schemas: [schema_a, schema_b],
          security_schemes: %{},
          source_contexts: %{}
        }
      )

    refs = manifest["schemas"] |> Enum.map(& &1["ref"])

    assert length(refs) == 2
    assert length(Enum.uniq(refs)) == 2
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
      extensions: %{}
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
      call: %{profile: :docs_fixture},
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
