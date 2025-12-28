defmodule Pristine.Codegen.ClientTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen.Elixir, as: ElixirCodegen
  alias Pristine.Manifest.Endpoint

  describe "render_client_module/3 with resources" do
    test "generates resource accessor functions" do
      endpoints = [
        %Endpoint{id: "create", resource: "models", method: "POST", path: "/models"},
        %Endpoint{id: "sample", resource: "sampling", method: "POST", path: "/sample"}
      ]

      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest(endpoints))

      # Resource accessors
      assert code =~ "def models(%__MODULE__{} = client)"
      assert code =~ "def sampling(%__MODULE__{} = client)"

      # Returns resource module instance
      assert code =~ "TestAPI.Models.with_client(client)"
      assert code =~ "TestAPI.Sampling.with_client(client)"
    end

    test "generates new/1 constructor" do
      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest([]))

      assert code =~ "def new(opts \\\\ [])"
      assert code =~ "Context.new(opts)"
    end

    test "generates defstruct with context" do
      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest([]))

      assert code =~ "defstruct [:context]"
    end

    test "includes ungrouped endpoints directly in client" do
      endpoints = [
        %Endpoint{id: "health", resource: nil, method: "GET", path: "/health"}
      ]

      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest(endpoints))

      assert code =~ "def health("
    end

    test "generates @type t specification" do
      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest([]))

      assert code =~ "@type t :: %__MODULE__{context: Context.t()}"
    end

    test "generates @spec for resource accessors" do
      endpoints = [
        %Endpoint{id: "test", resource: "models", method: "GET", path: "/test"}
      ]

      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest(endpoints))

      assert code =~ "@spec models(t()) :: TestAPI.Models.t()"
    end

    test "generates @doc for resource accessors" do
      endpoints = [
        %Endpoint{id: "test", resource: "models", method: "GET", path: "/test"}
      ]

      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest(endpoints))

      assert code =~ "@doc \"Access models resource endpoints.\""
    end

    test "handles mixed grouped and ungrouped endpoints" do
      endpoints = [
        %Endpoint{id: "create", resource: "models", method: "POST", path: "/models"},
        %Endpoint{id: "health", resource: nil, method: "GET", path: "/health"},
        %Endpoint{id: "sample", resource: "sampling", method: "POST", path: "/sample"}
      ]

      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest(endpoints))

      # Resource accessors
      assert code =~ "def models(%__MODULE__{} = client)"
      assert code =~ "def sampling(%__MODULE__{} = client)"

      # Ungrouped endpoint
      assert code =~ "def health("
    end

    test "deduplicates resource accessors" do
      endpoints = [
        %Endpoint{id: "create", resource: "models", method: "POST", path: "/models"},
        %Endpoint{id: "get", resource: "models", method: "GET", path: "/models/:id"}
      ]

      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest(endpoints))

      # Should only have one models accessor
      matches = Regex.scan(~r/def models\(%__MODULE__\{\} = client\)/, code)
      assert length(matches) == 1
    end

    test "handles snake_case resource names" do
      endpoints = [
        %Endpoint{id: "test", resource: "api_keys", method: "GET", path: "/api_keys"}
      ]

      code = ElixirCodegen.render_client_module("TestAPI.Client", build_manifest(endpoints))

      assert code =~ "def api_keys(%__MODULE__{} = client)"
      assert code =~ "TestAPI.ApiKeys.with_client(client)"
    end
  end

  # Helper to build manifest map
  defp build_manifest(endpoints) do
    %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: Enum.map(endpoints, &Map.from_struct/1),
      types: %{}
    }
  end
end
