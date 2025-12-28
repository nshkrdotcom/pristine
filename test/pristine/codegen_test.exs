defmodule Pristine.CodegenTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen

  describe "build_sources/2" do
    test "returns files for types and client" do
      manifest = %{
        name: "demo",
        version: "0.1.0",
        endpoints: [
          %{
            id: "sample",
            method: "POST",
            path: "/sampling",
            request: "SampleRequest",
            response: "SampleResponse"
          }
        ],
        types: %{
          "SampleRequest" => %{fields: %{prompt: %{type: "string", required: true}}}
        }
      }

      assert {:ok, sources} = Codegen.build_sources(manifest, output_dir: "lib/generated")
      assert Map.has_key?(sources, "lib/generated/types/sample_request.ex")
      assert Map.has_key?(sources, "lib/generated/client.ex")
    end

    test "returns files for resource modules" do
      manifest = %{
        name: "demo",
        version: "0.1.0",
        endpoints: [
          %{
            id: "create_model",
            method: "POST",
            path: "/models",
            resource: "models"
          },
          %{
            id: "sample",
            method: "POST",
            path: "/sample",
            resource: "sampling"
          }
        ],
        types: %{}
      }

      assert {:ok, sources} = Codegen.build_sources(manifest, output_dir: "lib/generated")
      assert Map.has_key?(sources, "lib/generated/resources/models.ex")
      assert Map.has_key?(sources, "lib/generated/resources/sampling.ex")
      assert Map.has_key?(sources, "lib/generated/client.ex")
    end

    test "client module includes resource accessors" do
      manifest = %{
        name: "demo",
        version: "0.1.0",
        endpoints: [
          %{
            id: "create",
            method: "POST",
            path: "/models",
            resource: "models"
          }
        ],
        types: %{}
      }

      assert {:ok, sources} = Codegen.build_sources(manifest, output_dir: "lib/generated")
      client_source = sources["lib/generated/client.ex"]

      assert client_source =~ "def models(%__MODULE__{} = client)"
      assert client_source =~ "Pristine.Generated.Models.with_client(client)"
    end

    test "handles mixed grouped and ungrouped endpoints" do
      manifest = %{
        name: "demo",
        version: "0.1.0",
        endpoints: [
          %{
            id: "create",
            method: "POST",
            path: "/models",
            resource: "models"
          },
          %{
            id: "health",
            method: "GET",
            path: "/health",
            resource: nil
          }
        ],
        types: %{}
      }

      assert {:ok, sources} = Codegen.build_sources(manifest, output_dir: "lib/generated")

      # Should have resource module for models
      assert Map.has_key?(sources, "lib/generated/resources/models.ex")

      # Client should have health endpoint (ungrouped)
      client_source = sources["lib/generated/client.ex"]
      assert client_source =~ "def health("
    end
  end
end
