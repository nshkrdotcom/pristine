defmodule Pristine.OpenAPITest do
  use ExUnit.Case, async: true

  alias Pristine.Manifest
  alias Pristine.OpenAPI

  describe "generate/2" do
    test "generates valid OpenAPI 3.1 structure" do
      manifest = build_test_manifest()

      {:ok, spec} = OpenAPI.generate(manifest)

      assert spec["openapi"] == "3.1.0"
      assert is_map(spec["info"])
      assert is_map(spec["paths"])
      assert is_map(spec["components"])
    end

    test "includes info section from manifest metadata" do
      manifest =
        build_test_manifest(%{
          name: "TestAPI",
          version: "1.0.0"
        })

      {:ok, spec} = OpenAPI.generate(manifest)

      assert spec["info"]["title"] == "TestAPI"
      assert spec["info"]["version"] == "1.0.0"
    end

    test "generates paths from endpoints" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", method: "GET", path: "/users/{id}"},
          %{id: "create_user", method: "POST", path: "/users"}
        ])

      {:ok, spec} = OpenAPI.generate(manifest)

      assert Map.has_key?(spec["paths"], "/users/{id}")
      assert Map.has_key?(spec["paths"]["/users/{id}"], "get")
      assert Map.has_key?(spec["paths"], "/users")
      assert Map.has_key?(spec["paths"]["/users"], "post")
    end

    test "generates path parameters from endpoint path" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", method: "GET", path: "/users/{user_id}/posts/{post_id}"}
        ])

      {:ok, spec} = OpenAPI.generate(manifest)

      params = spec["paths"]["/users/{user_id}/posts/{post_id}"]["get"]["parameters"]
      param_names = Enum.map(params, & &1["name"])

      assert "user_id" in param_names
      assert "post_id" in param_names
      assert Enum.all?(params, &(&1["in"] == "path"))
    end

    test "generates request body schema from endpoint request type" do
      manifest =
        build_test_manifest_with_typed_endpoint("create_user", %{
          method: "POST",
          path: "/users",
          request: "UserCreateRequest"
        })

      {:ok, spec} = OpenAPI.generate(manifest)

      body = spec["paths"]["/users"]["post"]["requestBody"]
      assert body["required"] == true
      assert is_map(body["content"]["application/json"]["schema"])
    end

    test "generates response schemas from endpoint response type" do
      manifest =
        build_test_manifest_with_typed_endpoint("get_user", %{
          method: "GET",
          path: "/users/{id}",
          response: "User"
        })

      {:ok, spec} = OpenAPI.generate(manifest)

      responses = spec["paths"]["/users/{id}"]["get"]["responses"]
      assert is_map(responses["200"])
      assert is_map(responses["200"]["content"]["application/json"]["schema"])
    end

    test "generates components/schemas from manifest types" do
      manifest =
        build_test_manifest_with_types(%{
          "User" => user_schema(),
          "Post" => post_schema()
        })

      {:ok, spec} = OpenAPI.generate(manifest)

      schemas = spec["components"]["schemas"]
      assert Map.has_key?(schemas, "User")
      assert Map.has_key?(schemas, "Post")
    end

    test "uses $ref for type references" do
      manifest =
        build_test_manifest_with_typed_endpoint("get_user", %{
          method: "GET",
          path: "/users/{id}",
          response: "User"
        })

      {:ok, spec} = OpenAPI.generate(manifest)

      schema =
        spec["paths"]["/users/{id}"]["get"]["responses"]["200"]["content"]["application/json"][
          "schema"
        ]

      assert schema["$ref"] == "#/components/schemas/User"
    end

    test "includes endpoint description when present" do
      manifest =
        build_test_manifest_with_endpoints([
          %{
            id: "get_user",
            method: "GET",
            path: "/users/{id}",
            description: "Retrieves a user by ID"
          }
        ])

      {:ok, spec} = OpenAPI.generate(manifest)

      assert spec["paths"]["/users/{id}"]["get"]["description"] == "Retrieves a user by ID"
    end

    test "formats output as JSON string with json option" do
      manifest = build_test_manifest()

      {:ok, json} = OpenAPI.generate(manifest, format: :json)

      assert is_binary(json)
      assert {:ok, _} = Jason.decode(json)
    end

    test "formats output as YAML string with yaml option" do
      manifest = build_test_manifest()

      {:ok, yaml} = OpenAPI.generate(manifest, format: :yaml)

      assert is_binary(yaml)
      assert yaml =~ "openapi:"
    end
  end

  describe "schema_to_openapi/1" do
    test "converts string type" do
      schema = %{type: :string}
      assert OpenAPI.schema_to_openapi(schema) == %{"type" => "string"}
    end

    test "converts string with format" do
      schema = %{type: :string, format: :email}
      assert OpenAPI.schema_to_openapi(schema) == %{"type" => "string", "format" => "email"}
    end

    test "converts integer type" do
      schema = %{type: :integer}
      assert OpenAPI.schema_to_openapi(schema) == %{"type" => "integer"}
    end

    test "converts integer with minimum/maximum" do
      schema = %{type: :integer, minimum: 1, maximum: 100}
      result = OpenAPI.schema_to_openapi(schema)
      assert result["type"] == "integer"
      assert result["minimum"] == 1
      assert result["maximum"] == 100
    end

    test "converts number type" do
      schema = %{type: :number}
      assert OpenAPI.schema_to_openapi(schema) == %{"type" => "number"}
    end

    test "converts boolean type" do
      schema = %{type: :boolean}
      assert OpenAPI.schema_to_openapi(schema) == %{"type" => "boolean"}
    end

    test "converts array type" do
      schema = %{type: {:array, :string}}
      result = OpenAPI.schema_to_openapi(schema)
      assert result["type"] == "array"
      assert result["items"] == %{"type" => "string"}
    end

    test "converts map type with properties" do
      schema = %{
        type: :map,
        properties: [
          {:name, :string, [required: true]},
          {:age, :integer, []}
        ]
      }

      result = OpenAPI.schema_to_openapi(schema)
      assert result["type"] == "object"
      assert result["properties"]["name"]["type"] == "string"
      assert result["required"] == ["name"]
    end

    test "converts literal type to const" do
      schema = %{type: {:literal, "fixed_value"}}
      result = OpenAPI.schema_to_openapi(schema)
      assert result["const"] == "fixed_value"
    end

    test "converts union type to oneOf" do
      schema = %{type: {:union, [:string, :integer]}}
      result = OpenAPI.schema_to_openapi(schema)
      assert is_list(result["oneOf"])
      assert %{"type" => "string"} in result["oneOf"]
      assert %{"type" => "integer"} in result["oneOf"]
    end
  end

  # Helper functions to build test manifests

  defp build_test_manifest(attrs \\ %{}) do
    base = %{
      name: Map.get(attrs, :name, "TestAPI"),
      version: Map.get(attrs, :version, "1.0.0"),
      endpoints: [
        %{id: "test", method: "GET", path: "/test"}
      ],
      types: %{
        "TestType" => %{fields: %{name: %{type: "string", required: true}}}
      }
    }

    {:ok, manifest} = Manifest.load(base)
    manifest
  end

  defp build_test_manifest_with_endpoints(endpoints) do
    endpoint_defs =
      Enum.map(endpoints, fn ep ->
        %{
          id: ep[:id] || ep["id"],
          method: ep[:method] || ep["method"] || "GET",
          path: ep[:path] || ep["path"],
          description: ep[:description] || ep["description"],
          request: ep[:request] || ep["request"],
          response: ep[:response] || ep["response"],
          resource: ep[:resource] || ep["resource"]
        }
      end)

    input = %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: endpoint_defs,
      types: %{
        "User" => user_schema(),
        "Post" => post_schema()
      }
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end

  defp build_test_manifest_with_typed_endpoint(id, attrs) do
    endpoint = %{
      id: id,
      method: attrs[:method] || attrs["method"] || "GET",
      path: attrs[:path] || attrs["path"],
      request: attrs[:request] || attrs["request"],
      response: attrs[:response] || attrs["response"]
    }

    input = %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: [endpoint],
      types: %{
        "User" => user_schema(),
        "UserCreateRequest" => user_create_schema()
      }
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end

  defp build_test_manifest_with_types(types) do
    input = %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: [%{id: "test", method: "GET", path: "/test"}],
      types: types
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end

  defp user_schema do
    %{
      fields: %{
        id: %{type: "string", required: true},
        name: %{type: "string", required: true},
        email: %{type: "string", required: false}
      }
    }
  end

  defp user_create_schema do
    %{
      fields: %{
        name: %{type: "string", required: true},
        email: %{type: "string", required: true}
      }
    }
  end

  defp post_schema do
    %{
      fields: %{
        id: %{type: "string", required: true},
        title: %{type: "string", required: true},
        content: %{type: "string", required: false}
      }
    }
  end
end
