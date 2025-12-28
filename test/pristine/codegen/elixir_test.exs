defmodule Pristine.Codegen.ElixirTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen.Elixir, as: Codegen

  describe "render_type_module/3" do
    test "renders a type module" do
      type_def = %{
        fields: %{
          prompt: %{type: "string", required: true, min_length: 1},
          sampling_params: %{type: "string", required: true}
        }
      }

      source = Codegen.render_type_module("Pristine.Generated.Types", "SampleRequest", type_def)

      assert source =~ "defmodule Pristine.Generated.Types.SampleRequest"
      assert source =~ "def schema()"
      assert source =~ "Sinter.Schema.define"
      assert source =~ "min_length"
    end
  end

  describe "render_client_module/2" do
    test "renders a client module" do
      manifest = %{
        name: "tinkex",
        version: "0.3.4",
        endpoints: [
          %{
            id: "sample",
            method: "POST",
            path: "/sampling",
            request: "SampleRequest",
            response: "SampleResponse"
          }
        ],
        types: %{}
      }

      source = Codegen.render_client_module("Pristine.Generated.Client", manifest)

      assert source =~ "defmodule Pristine.Generated.Client"
      assert source =~ "def sample"
      assert source =~ "Pristine.Runtime.execute"
    end

    test "generates module with @moduledoc" do
      manifest = %{
        name: "TestAPI",
        version: "1.0.0",
        endpoints: [],
        types: %{}
      }

      source = Codegen.render_client_module("TestAPI.Client", manifest)

      assert source =~ "defmodule TestAPI.Client do"
      assert source =~ "@moduledoc"
      assert source =~ "TestAPI"
      assert source =~ "v1.0.0"
    end
  end

  describe "render_endpoint_fn/1" do
    test "generates @doc from endpoint description" do
      endpoint = %{
        id: "create_model",
        method: "POST",
        path: "/api/v1/create_model",
        description: "Creates a new model.\n\nPass a LoRA config to create a new LoRA adapter."
      }

      code = Codegen.render_endpoint_fn(endpoint)

      assert code =~ "@doc"
      assert code =~ "Creates a new model."
      assert code =~ "Pass a LoRA config"
    end

    test "generates @spec with request and response types" do
      endpoint = %{
        id: "create_model",
        method: "POST",
        path: "/api/v1/create_model",
        request: "CreateModelRequest",
        response: "UntypedAPIFuture"
      }

      code = Codegen.render_endpoint_fn(endpoint)

      assert code =~ "@spec create_model(map(), Pristine.Core.Context.t(), keyword())"
      assert code =~ "{:ok, term()} | {:error, term()}"
    end

    test "handles nil description gracefully" do
      endpoint = %{
        id: "test",
        method: "GET",
        path: "/test",
        description: nil
      }

      code = Codegen.render_endpoint_fn(endpoint)

      # Should not crash, should generate valid code
      refute code =~ "@doc nil"
      assert code =~ "def test"
    end

    test "handles empty description" do
      endpoint = %{
        id: "test",
        method: "GET",
        path: "/test",
        description: ""
      }

      code = Codegen.render_endpoint_fn(endpoint)

      # Should not generate empty @doc
      refute code =~ ~s(@doc "")
      assert code =~ "def test"
    end
  end
end
