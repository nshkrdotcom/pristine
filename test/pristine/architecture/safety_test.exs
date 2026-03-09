defmodule Pristine.Architecture.SafetyTest do
  use ExUnit.Case, async: false
  import Mox

  alias Pristine.Codegen.{Resource, Type}
  alias Pristine.Core.{Context, Pipeline, Request, Response}
  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "type codegen does not create atoms from manifest field names" do
    Type.render_type_module("MyAPI.Types.WarmType", "WarmType", %{
      "fields" => [%{"name" => "warm_field", "type" => "string", "required" => true}]
    })

    field_name = "field_#{System.unique_integer([:positive])}"
    type_def = %{"fields" => [%{"name" => field_name, "type" => "string", "required" => true}]}
    before_count = :erlang.system_info(:atom_count)

    code = Type.render_type_module("MyAPI.Types.SafeType", "SafeType", type_def)

    assert code =~ ":#{field_name}"
    assert :erlang.system_info(:atom_count) == before_count
  end

  test "resource codegen does not create atoms from path params or required fields" do
    warm_endpoint = %Endpoint{
      id: "warm_create",
      method: "POST",
      path: "/resources/{warm_path}",
      resource: "resources",
      request: "WarmRequest"
    }

    Resource.render_resource_module("MyAPI.Resources", "resources", [warm_endpoint], %{
      "WarmRequest" => %{fields: %{"warm_field" => %{type: "string", required: true}}}
    })

    path_param = "path_#{System.unique_integer([:positive])}"
    field_name = "field_#{System.unique_integer([:positive])}"

    endpoint = %Endpoint{
      id: "create",
      method: "POST",
      path: "/resources/{#{path_param}}",
      resource: "resources",
      request: "CreateResource"
    }

    types = %{
      "CreateResource" => %{
        fields: %{
          field_name => %{type: "string", required: true}
        }
      }
    }

    before_count = :erlang.system_info(:atom_count)

    code = Resource.render_resource_module("MyAPI.Resources", "resources", [endpoint], types)

    assert code =~
             "def create(%__MODULE__{context: context}, #{path_param}, #{field_name}, opts \\\\ [])"

    assert :erlang.system_info(:atom_count) == before_count
  end

  test "pipeline telemetry does not atomize unknown HTTP methods" do
    unique = System.unique_integer([:positive])
    method = "CUSTOM#{unique}"

    manifest = %{
      name: "safe_api",
      version: "1.0.0",
      endpoints: [
        %{
          id: "custom_call",
          method: method,
          path: "/custom",
          request: "SafeRequest",
          response: "SafeResponse"
        }
      ],
      types: %{
        "SafeRequest" => %{fields: %{payload: %{type: "string", required: true}}},
        "SafeResponse" => %{fields: %{ok: %{type: "boolean", required: true}}}
      }
    }

    {:ok, manifest} = Manifest.load(manifest)

    context = %Context{
      base_url: "https://example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }

    payload = %{"payload" => "ok"}

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"payload\":\"ok\"}"}
    end)

    expect(Pristine.TransportMock, :send, fn %Request{method: ^method}, ^context ->
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", _schema, _opts ->
      {:ok, %{"ok" => true}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts -> fun.() end)
    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts -> fun.() end)
    expect(Pristine.CircuitBreakerMock, :call, fn "custom_call", fun, _opts -> fun.() end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, metadata, _measurements ->
      assert metadata.method == String.downcase(method)
      :ok
    end)

    assert {:ok, %{"ok" => true}} = Pipeline.execute(manifest, "custom_call", payload, context)
  end

  test "request planning preserves binary pool types without atomizing them" do
    unique = System.unique_integer([:positive])
    pool_type = "resource_#{unique}"

    endpoint = %Endpoint{id: "fetch", method: "GET", path: "/items", resource: nil}

    context = %Context{
      base_url: "https://example.com",
      pool_base: :shared_pool,
      pool_manager: Pristine.Adapters.PoolManager,
      headers: %{}
    }

    request = Pipeline.build_request(endpoint, nil, nil, context, pool_type: pool_type)

    assert request.metadata.pool_type == pool_type
    assert request.metadata.pool_name == :shared_pool
  end
end
