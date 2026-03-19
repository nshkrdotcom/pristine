defmodule Pristine.Architecture.SafetyTest do
  use ExUnit.Case, async: false
  import Mox

  alias Pristine.Core.{Context, EndpointMetadata, Pipeline, Request, Response}

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "pipeline telemetry does not atomize unknown HTTP methods" do
    unique = System.unique_integer([:positive])
    method = "CUSTOM#{unique}"

    endpoint = %EndpointMetadata{
      id: "custom_call",
      method: method,
      path: "/custom",
      headers: %{},
      query: %{}
    }

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

    assert {:ok, %{"ok" => true}} = Pipeline.execute_endpoint(endpoint, payload, context)
  end

  test "request planning preserves binary pool types without atomizing them" do
    unique = System.unique_integer([:positive])
    pool_type = "resource_#{unique}"

    endpoint = %EndpointMetadata{id: "fetch", method: "GET", path: "/items", resource: nil}

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

  test "request planning omits pool_name metadata when no pool is resolved" do
    endpoint = %EndpointMetadata{id: "fetch", method: "GET", path: "/items", resource: nil}

    context = %Context{
      base_url: "https://example.com",
      headers: %{}
    }

    request = Pipeline.build_request(endpoint, nil, nil, context, [])

    assert request.metadata.pool_type == :default
    refute Map.has_key?(request.metadata, :pool_name)
  end
end
