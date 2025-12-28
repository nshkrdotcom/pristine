defmodule Pristine.Test.FixturesTest do
  use ExUnit.Case, async: true

  alias Pristine.Manifest
  alias Pristine.Test.Fixtures

  describe "generate/2" do
    test "generates fixture for string type" do
      schema = %{type: :string}

      fixture = Fixtures.generate(schema)

      assert is_binary(fixture)
    end

    test "generates fixture with string constraints" do
      schema = %{type: :string, min_length: 5, max_length: 10}

      fixture = Fixtures.generate(schema)

      assert String.length(fixture) >= 5
      assert String.length(fixture) <= 10
    end

    test "generates fixture for integer type" do
      schema = %{type: :integer}

      fixture = Fixtures.generate(schema)

      assert is_integer(fixture)
    end

    test "generates fixture with integer constraints" do
      schema = %{type: :integer, minimum: 1, maximum: 100}

      fixture = Fixtures.generate(schema)

      assert fixture >= 1
      assert fixture <= 100
    end

    test "generates fixture for number type" do
      schema = %{type: :number}

      fixture = Fixtures.generate(schema)

      assert is_number(fixture)
    end

    test "generates fixture for boolean type" do
      schema = %{type: :boolean}

      fixture = Fixtures.generate(schema)

      assert is_boolean(fixture)
    end

    test "generates fixture for array type" do
      schema = %{type: {:array, :string}}

      fixture = Fixtures.generate(schema)

      assert is_list(fixture)
      assert Enum.all?(fixture, &is_binary/1)
    end

    test "generates fixture with array length constraints" do
      schema = %{type: {:array, :integer}, min_items: 2, max_items: 5}

      fixture = Fixtures.generate(schema)

      assert length(fixture) >= 2
      assert length(fixture) <= 5
    end

    test "generates fixture for map type with properties" do
      schema = %{
        type: :map,
        properties: [
          {:name, :string, [required: true]},
          {:age, :integer, []}
        ]
      }

      fixture = Fixtures.generate(schema)

      assert is_map(fixture)
      assert is_binary(fixture["name"])
      assert is_integer(fixture["age"]) or is_nil(fixture["age"])
    end

    test "includes all required fields" do
      schema = %{
        type: :map,
        properties: [
          {:id, :string, [required: true]},
          {:name, :string, [required: true]},
          {:optional, :string, []}
        ]
      }

      fixture = Fixtures.generate(schema)

      assert Map.has_key?(fixture, "id")
      assert Map.has_key?(fixture, "name")
    end

    test "generates fixture for literal type" do
      schema = %{type: {:literal, "constant"}}

      fixture = Fixtures.generate(schema)

      assert fixture == "constant"
    end

    test "generates fixture for union type" do
      schema = %{type: {:union, [:string, :integer]}}

      fixture = Fixtures.generate(schema)

      assert is_binary(fixture) or is_integer(fixture)
    end

    test "respects seed option for reproducibility" do
      schema = %{type: :integer}

      fixture1 = Fixtures.generate(schema, seed: 12_345)
      fixture2 = Fixtures.generate(schema, seed: 12_345)

      assert fixture1 == fixture2
    end

    test "generates different fixtures without seed" do
      schema = %{type: :string, min_length: 20}

      fixtures = for _ <- 1..10, do: Fixtures.generate(schema)
      unique = Enum.uniq(fixtures)

      # Should have some variation (at least 2 unique values in 10 tries)
      assert length(unique) >= 2
    end
  end

  describe "generate_list/3" do
    test "generates list of fixtures" do
      schema = %{type: :string}

      fixtures = Fixtures.generate_list(schema, 5)

      assert length(fixtures) == 5
      assert Enum.all?(fixtures, &is_binary/1)
    end

    test "generates specified number of fixtures" do
      schema = %{type: :integer}

      fixtures = Fixtures.generate_list(schema, 10)

      assert length(fixtures) == 10
    end
  end

  describe "for_manifest/2" do
    test "generates fixtures for all types in manifest" do
      manifest =
        build_test_manifest_with_types(%{
          "User" => user_schema(),
          "Post" => post_schema()
        })

      fixtures = Fixtures.for_manifest(manifest)

      assert Map.has_key?(fixtures, "User")
      assert Map.has_key?(fixtures, "Post")
    end

    test "each type fixture is a valid map" do
      manifest =
        build_test_manifest_with_types(%{
          "User" => user_schema()
        })

      fixtures = Fixtures.for_manifest(manifest)

      assert is_map(fixtures["User"])
    end
  end

  describe "for_endpoint/3" do
    test "generates request and response fixtures for endpoint" do
      manifest = build_test_manifest_with_typed_endpoint()
      endpoint = get_endpoint(manifest, "create_user")

      fixtures = Fixtures.for_endpoint(manifest, endpoint)

      assert Map.has_key?(fixtures, :request)
      assert Map.has_key?(fixtures, :response)
    end

    test "request fixture includes required fields" do
      manifest = build_test_manifest_with_typed_endpoint()
      endpoint = get_endpoint(manifest, "create_user")

      fixtures = Fixtures.for_endpoint(manifest, endpoint)

      # Request fixture should have the fields from UserCreate type
      assert is_map(fixtures.request)
    end

    test "returns nil for missing request/response types" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "simple", method: "GET", path: "/simple"}
        ])

      endpoint = get_endpoint(manifest, "simple")

      fixtures = Fixtures.for_endpoint(manifest, endpoint)

      assert is_nil(fixtures.request)
      assert is_nil(fixtures.response)
    end
  end

  describe "sample_manifest/1" do
    test "returns a valid manifest" do
      manifest = Fixtures.sample_manifest()

      assert %Manifest{} = manifest
      assert is_binary(manifest.name)
      assert is_binary(manifest.version)
    end

    test "allows overriding name" do
      manifest = Fixtures.sample_manifest(name: "CustomAPI")

      assert manifest.name == "CustomAPI"
    end

    test "allows overriding version" do
      manifest = Fixtures.sample_manifest(version: "2.0.0")

      assert manifest.version == "2.0.0"
    end
  end

  # Helper functions

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

  defp build_test_manifest_with_typed_endpoint do
    input = %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: [
        %{
          id: "create_user",
          method: "POST",
          path: "/users",
          request: "UserCreate",
          response: "User"
        }
      ],
      types: %{
        "User" => user_schema(),
        "UserCreate" => user_create_schema()
      }
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end

  defp build_test_manifest_with_endpoints(endpoints) do
    endpoint_defs =
      Enum.map(endpoints, fn ep ->
        %{
          id: ep[:id],
          method: ep[:method],
          path: ep[:path],
          request: ep[:request],
          response: ep[:response]
        }
      end)

    input = %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: endpoint_defs,
      types: %{"TestType" => %{fields: %{name: %{type: "string", required: true}}}}
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end

  defp get_endpoint(%Manifest{endpoints: endpoints}, id) do
    Map.get(endpoints, id)
  end

  defp user_schema do
    %{
      fields: %{
        id: %{type: "string", required: true},
        name: %{type: "string", required: true}
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
        title: %{type: "string", required: true}
      }
    }
  end
end
