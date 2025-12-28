defmodule Pristine.DocsTest do
  use ExUnit.Case, async: true

  alias Pristine.Docs
  alias Pristine.Manifest

  describe "generate/2" do
    test "generates markdown documentation" do
      manifest = build_test_manifest()

      {:ok, docs} = Docs.generate(manifest)

      assert is_binary(docs)
      assert docs =~ "# TestAPI"
    end

    test "includes API overview section" do
      manifest =
        build_test_manifest(%{
          name: "TestAPI",
          version: "1.0.0"
        })

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "## Overview"
      assert docs =~ "Version: 1.0.0"
    end

    test "generates table of contents" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", resource: "users", method: "GET", path: "/users/{id}"},
          %{id: "create_user", resource: "users", method: "POST", path: "/users"},
          %{id: "list_posts", resource: "posts", method: "GET", path: "/posts"}
        ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "## Table of Contents"
      assert docs =~ "- [Users](#users)"
      assert docs =~ "- [Posts](#posts)"
    end

    test "groups endpoints by resource" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", resource: "users", method: "GET", path: "/users/{id}"},
          %{id: "create_user", resource: "users", method: "POST", path: "/users"}
        ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "## Users"
      assert docs =~ "### GET /users/{id}"
      assert docs =~ "### POST /users"
    end

    test "includes endpoint description" do
      manifest =
        build_test_manifest_with_endpoints([
          %{
            id: "get_user",
            method: "GET",
            path: "/users/{id}",
            description: "Retrieves a user by ID"
          }
        ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "Retrieves a user by ID"
    end

    test "documents request parameters" do
      manifest =
        build_test_manifest_with_endpoints([
          %{
            id: "get_user",
            method: "GET",
            path: "/users/{id}"
          }
        ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "#### Parameters"
      assert docs =~ "| Parameter | Type | Required | Description |"
      assert docs =~ "| `id` | string | Yes |"
    end

    test "documents request body schema" do
      manifest = build_test_manifest_with_typed_endpoint()

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "#### Request Body"
    end

    test "documents response schema" do
      manifest = build_test_manifest_with_response_endpoint()

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "#### Response"
    end

    test "generates type reference section" do
      manifest =
        build_test_manifest_with_types(%{
          "User" => user_schema()
        })

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "## Type Reference"
      assert docs =~ "### User"
    end

    test "documents type fields" do
      manifest =
        build_test_manifest_with_types(%{
          "User" => user_schema_with_fields()
        })

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "| Field | Type | Required | Description |"
      assert docs =~ "| `id` |"
      assert docs =~ "| `name` |"
    end

    test "generates example requests when examples option is true" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "create_user", method: "POST", path: "/users", request: "UserCreate"}
        ])

      {:ok, docs} = Docs.generate(manifest, examples: true)

      assert docs =~ "#### Example"
      assert docs =~ "```elixir"
    end
  end

  describe "generate_html/2" do
    test "generates HTML documentation" do
      manifest = build_test_manifest()

      {:ok, html} = Docs.generate_html(manifest)

      assert html =~ "<html>"
      assert html =~ "<h1>TestAPI</h1>"
    end

    test "includes CSS styles" do
      manifest = build_test_manifest()

      {:ok, html} = Docs.generate_html(manifest)

      assert html =~ "<style>"
      assert html =~ "font-family"
    end
  end

  # Helper functions

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
        "UserCreate" => user_create_schema()
      }
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end

  defp build_test_manifest_with_typed_endpoint do
    endpoint = %{
      id: "create_user",
      method: "POST",
      path: "/users",
      request: "UserCreate"
    }

    input = %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: [endpoint],
      types: %{
        "User" => user_schema(),
        "UserCreate" => user_create_schema()
      }
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end

  defp build_test_manifest_with_response_endpoint do
    endpoint = %{
      id: "get_user",
      method: "GET",
      path: "/users/{id}",
      response: "User"
    }

    input = %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: [endpoint],
      types: %{
        "User" => user_schema()
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
        name: %{type: "string", required: true}
      }
    }
  end

  defp user_schema_with_fields do
    %{
      fields: %{
        id: %{type: "string", required: true, description: "Unique identifier"},
        name: %{type: "string", required: true, description: "User name"},
        email: %{type: "string", required: false, description: "Email address"}
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
end
