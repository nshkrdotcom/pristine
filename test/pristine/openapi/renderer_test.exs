defmodule Pristine.OpenAPI.RendererTest do
  use ExUnit.Case, async: true

  alias OpenAPI.Processor.Operation.Param
  alias OpenAPI.Processor.Schema
  alias OpenAPI.Renderer.File
  alias OpenAPI.Renderer.State
  alias OpenAPI.Spec.ExternalDocumentation
  alias Pristine.OpenAPI.DocComposer
  alias Pristine.OpenAPI.NamedTypedMapFixture
  alias Pristine.OpenAPI.Renderer, as: OpenAPIRenderer

  test "rewrites nested pristine module references to local aliases in rendered source" do
    source = """
    defmodule Example do
      @moduledoc false
      use Pristine.SDK.OpenAPI.Operation

      @spec provider() :: Pristine.SDK.OAuth2.Provider.t()
      def provider do
        Pristine.SDK.OAuth2.Provider.new(name: "example")
      end

      def decode(data) do
        Pristine.SDK.OpenAPI.Runtime.decode_module_type(__MODULE__, :t, data)
      end
    end
    """

    source = OpenAPIRenderer.rewrite_nested_module_aliases_in_source(source)

    assert source =~ "alias Pristine.SDK.OAuth2, as: OAuth2"
    assert source =~ "alias Pristine.SDK.OpenAPI.Runtime, as: OpenAPIRuntime"
    assert source =~ "@spec provider() :: OAuth2.Provider.t()"
    assert source =~ "OAuth2.Provider.new(name: \"example\")"
    assert source =~ "OpenAPIRuntime.decode_module_type(__MODULE__, :t, data)"
    refute source =~ "Pristine.SDK.OAuth2.Provider.new"
    refute source =~ "Pristine.SDK.OpenAPI.Runtime.decode_module_type"
  end

  test "inserts runtime alias when generated source already uses the short alias" do
    source = """
    defmodule Example do
      @moduledoc false

      def decode(data) do
        OpenAPIRuntime.decode_module_type(__MODULE__, :t, data)
      end
    end
    """

    source = OpenAPIRenderer.rewrite_nested_module_aliases_in_source(source)

    assert source =~ "alias Pristine.SDK.OpenAPI.Runtime, as: OpenAPIRuntime"
    assert source =~ "OpenAPIRuntime.decode_module_type(__MODULE__, :t, data)"
    refute source =~ "\n\n\n"
  end

  test "skips operation rendering for schema-only files with orphan typed maps" do
    orphan_ref = make_ref()

    file = %File{
      module: Audio,
      operations: [],
      schemas: [
        %Schema{
          context: [{:field, orphan_ref, "children"}],
          fields: [],
          module_name: Audio,
          output_format: :typed_map,
          ref: make_ref(),
          type_name: :t
        }
      ]
    }

    task =
      Task.async(fn ->
        OpenAPIRenderer.render_operations(%State{}, file)
      end)

    assert Task.await(task, 100) == []
  end

  test "renders operation docs through the shared composer" do
    profile = :"renderer_doc_#{System.unique_integer([:positive])}"
    source_contexts = %{{:get, "/widgets"} => %{title: "Widgets reference"}}

    on_exit(fn -> Application.delete_env(:oapi_generator, profile) end)

    Application.put_env(:oapi_generator, profile, output: [source_contexts: source_contexts])

    state = %State{profile: profile}

    operation = %{
      function_name: :list_widgets,
      module_name: Widgets,
      request_body: [],
      request_body_docs: nil,
      request_header_parameters: [],
      request_method: :get,
      request_path: "/widgets",
      request_path_parameters: [],
      request_query_parameters: [
        %Param{name: "cursor", description: "Pagination cursor"}
      ],
      response_docs: [
        %{status: 200, description: "Widget list", content_types: ["application/json"]}
      ],
      responses: [],
      security: [%{"bearerAuth" => []}],
      summary: "List widgets",
      description: "Returns every widget.",
      external_docs: %ExternalDocumentation{
        description: "API docs",
        url: "https://example.com/widgets"
      },
      tags: ["Widgets"],
      deprecated: false,
      docstring: "",
      extensions: %{}
    }

    expected =
      quote do
        @doc unquote(DocComposer.operation_doc(operation, source_contexts: source_contexts))
      end

    assert Macro.to_string(OpenAPIRenderer.render_operation_doc(state, operation)) ==
             Macro.to_string(expected)
  end

  test "renders module docs through the shared composer" do
    profile = :"renderer_moduledoc_#{System.unique_integer([:positive])}"

    on_exit(fn -> Application.delete_env(:oapi_generator, profile) end)

    Application.put_env(:oapi_generator, profile, output: [source_contexts: %{}])

    state = %State{profile: profile}

    operation = %{
      function_name: :list_widgets,
      module_name: Widgets,
      request_body: [],
      request_body_docs: nil,
      request_header_parameters: [],
      request_method: :get,
      request_path: "/widgets",
      request_path_parameters: [],
      request_query_parameters: [],
      response_docs: [],
      responses: [],
      security: [%{"bearerAuth" => []}],
      summary: "List widgets",
      description: "Returns every widget.",
      external_docs: nil,
      tags: ["Widgets"],
      deprecated: false,
      docstring: "",
      extensions: %{}
    }

    file = %File{module: Widgets, operations: [operation], schemas: []}

    expected =
      quote do
        @moduledoc unquote(DocComposer.module_doc(file, source_contexts: %{}))
      end

    assert Macro.to_string(OpenAPIRenderer.render_moduledoc(state, file)) ==
             Macro.to_string(expected)
  end

  test "renders named typed-map modules when public operation types reference them" do
    fixture = NamedTypedMapFixture.run_bridge!(:renderer)
    on_exit(fn -> NamedTypedMapFixture.cleanup(fixture) end)

    assert NamedTypedMapFixture.generated_path?(fixture, "/o_auth.ex")
    assert NamedTypedMapFixture.generated_path?(fixture, "/user.ex")
    assert NamedTypedMapFixture.generated_path?(fixture, "/workspace.ex")

    user_source = NamedTypedMapFixture.source!(fixture, "/user.ex")
    workspace_source = NamedTypedMapFixture.source!(fixture, "/workspace.ex")

    assert user_source =~ "@type t ::"
    assert user_source =~ "def __openapi_fields__(:t)"
    assert user_source =~ "def __schema__(:t)"

    assert workspace_source =~ "@type t ::"
    assert workspace_source =~ "def __openapi_fields__(:t)"
    assert workspace_source =~ "def __schema__(:t)"
  end
end
