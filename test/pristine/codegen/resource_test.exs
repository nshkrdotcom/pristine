defmodule Pristine.Codegen.ResourceTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen.Resource
  alias Pristine.Manifest.Endpoint

  describe "group_by_resource/1" do
    test "groups endpoints by resource field" do
      endpoints = [
        %Endpoint{id: "create_model", resource: "models", method: "POST", path: "/models"},
        %Endpoint{id: "get_model", resource: "models", method: "GET", path: "/models/:id"},
        %Endpoint{id: "sample", resource: "sampling", method: "POST", path: "/sample"},
        %Endpoint{id: "health", resource: nil, method: "GET", path: "/health"}
      ]

      grouped = Resource.group_by_resource(endpoints)

      assert Map.has_key?(grouped, "models")
      assert Map.has_key?(grouped, "sampling")
      assert Map.has_key?(grouped, nil)
      assert length(grouped["models"]) == 2
      assert length(grouped["sampling"]) == 1
      assert length(grouped[nil]) == 1
    end

    test "returns empty map for empty list" do
      assert Resource.group_by_resource([]) == %{}
    end
  end

  describe "render_resource_module/4" do
    test "generates module with all endpoint functions" do
      endpoints = [
        %Endpoint{
          id: "create",
          method: "POST",
          path: "/api/v1/models",
          resource: "models",
          description: "Create a new model",
          request: "CreateModelRequest",
          response: "Model"
        },
        %Endpoint{
          id: "get",
          method: "GET",
          path: "/api/v1/models/:id",
          resource: "models",
          description: "Get a model by ID"
        }
      ]

      types = %{
        "CreateModelRequest" => %{
          fields: %{
            name: %{type: "string", required: true}
          }
        }
      }

      code = Resource.render_resource_module("MyAPI.Models", "models", endpoints, types)

      # Module definition
      assert code =~ "defmodule MyAPI.Models do"

      # Module doc
      assert code =~ "@moduledoc"
      assert code =~ "models"

      # Both functions
      assert code =~ "def create("
      assert code =~ "def get("

      # Docs
      assert code =~ "Create a new model"
      assert code =~ "Get a model by ID"
    end

    test "generates with_client/1 function" do
      endpoints = [
        %Endpoint{id: "test", resource: "test", method: "GET", path: "/test"}
      ]

      code = Resource.render_resource_module("MyAPI.Test", "test", endpoints, %{})

      assert code =~ "def with_client(%{context: context})"
      assert code =~ "%__MODULE__{context: context}"
    end

    test "generates defstruct with context" do
      endpoints = [
        %Endpoint{id: "test", resource: "test", method: "GET", path: "/test"}
      ]

      code = Resource.render_resource_module("MyAPI.Test", "test", endpoints, %{})

      assert code =~ "defstruct [:context]"
      assert code =~ "@type t :: %__MODULE__{context:"
    end

    test "generates @spec for each endpoint function" do
      endpoints = [
        %Endpoint{id: "create", resource: "test", method: "POST", path: "/test"}
      ]

      code = Resource.render_resource_module("MyAPI.Test", "test", endpoints, %{})

      assert code =~ "@spec create(t(), keyword())"
      assert code =~ "{:ok, term()} | {:error, Pristine.Error.t()}"
    end

    test "handles endpoints without description" do
      endpoints = [
        %Endpoint{id: "test", resource: "test", method: "GET", path: "/test", description: nil}
      ]

      code = Resource.render_resource_module("MyAPI.Test", "test", endpoints, %{})

      # Should still generate valid code
      assert code =~ "def test("
      # Should not have a @doc with nil
      refute code =~ "@doc nil"
    end

    test "renders path params and typed arguments" do
      endpoints = [
        %Endpoint{
          id: "get",
          method: "GET",
          path: "/api/v1/models/:id",
          resource: "models",
          request: "GetModelRequest"
        }
      ]

      types = %{
        "GetModelRequest" => %{
          fields: %{
            id: %{type: "string", required: true},
            include: %{type: "string", required: false}
          }
        }
      }

      code = Resource.render_resource_module("MyAPI.Models", "models", endpoints, types)

      assert code =~ "def get(%__MODULE__{context: context}, id, opts \\\\ [])"
      assert code =~ "path_params = %{"
      assert code =~ "\"id\" => id"
      refute code =~ "\"id\" => encode_ref"
    end

    test "generates async variants for async endpoints" do
      endpoints = [
        %Endpoint{
          id: "create",
          method: "POST",
          path: "/api/v1/models",
          resource: "models",
          async: true,
          request: "CreateModelRequest",
          response: "Model"
        }
      ]

      types = %{
        "CreateModelRequest" => %{
          fields: %{
            name: %{type: "string", required: true}
          }
        }
      }

      code = Resource.render_resource_module("MyAPI.Models", "models", endpoints, types)

      assert code =~ "def create_async("
      assert code =~ "Runtime.execute_future"
    end
  end

  describe "render_all_resource_modules/2" do
    test "generates one module per resource" do
      endpoints = [
        %Endpoint{id: "create_model", resource: "models", method: "POST", path: "/models"},
        %Endpoint{id: "sample", resource: "sampling", method: "POST", path: "/sample"}
      ]

      modules = Resource.render_all_resource_modules("TestAPI", endpoints)

      assert Map.has_key?(modules, "TestAPI.Models")
      assert Map.has_key?(modules, "TestAPI.Sampling")
    end

    test "capitalizes resource name for module" do
      endpoints = [
        %Endpoint{id: "test", resource: "my_resource", method: "GET", path: "/test"}
      ]

      modules = Resource.render_all_resource_modules("TestAPI", endpoints)

      assert Map.has_key?(modules, "TestAPI.MyResource")
    end

    test "excludes endpoints with nil resource" do
      endpoints = [
        %Endpoint{id: "test", resource: nil, method: "GET", path: "/test"},
        %Endpoint{id: "other", resource: "models", method: "GET", path: "/other"}
      ]

      modules = Resource.render_all_resource_modules("TestAPI", endpoints)

      assert Map.has_key?(modules, "TestAPI.Models")
      refute Map.has_key?(modules, "TestAPI.")
      assert map_size(modules) == 1
    end

    test "handles single-word resource names" do
      endpoints = [
        %Endpoint{id: "test", resource: "models", method: "GET", path: "/test"}
      ]

      modules = Resource.render_all_resource_modules("TestAPI", endpoints)

      assert Map.has_key?(modules, "TestAPI.Models")
    end
  end

  describe "resource_to_module_name/2" do
    test "converts snake_case to PascalCase" do
      assert Resource.resource_to_module_name("MyAPI", "my_resource") == "MyAPI.MyResource"
      assert Resource.resource_to_module_name("MyAPI", "models") == "MyAPI.Models"
      assert Resource.resource_to_module_name("MyAPI", "api_keys") == "MyAPI.ApiKeys"
    end
  end
end
