defmodule Pristine.RuntimeTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Request, Response}
  alias Pristine.Manifest.Endpoint
  alias Pristine.OpenAPI.Client, as: OpenAPIClient
  alias Pristine.Runtime

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "hydrates runtime context from manifest metadata and endpoint defaults" do
    manifest = %{
      name: "demo",
      version: "0.1.0",
      base_url: "https://api.example.com",
      defaults: %{
        retry: "default",
        headers: %{"X-App" => "pristine"}
      },
      retry_policies: %{
        "default" => %{max_attempts: 7}
      },
      endpoints: [
        %{
          id: "sample",
          method: "POST",
          path: "/sample",
          request: "SampleRequest",
          response: "SampleResponse",
          headers: %{"X-Endpoint" => "1"}
        }
      ],
      types: %{
        "SampleRequest" => %{fields: %{prompt: %{type: "string", required: true}}},
        "SampleResponse" => %{fields: %{ok: %{type: "boolean", required: true}}}
      }
    }

    payload = %{"prompt" => "hi"}

    context = %Context{
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "sample", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, headers: headers},
                                             hydrated_context ->
      assert url == "https://api.example.com/sample"
      assert headers["X-App"] == "pristine"
      assert headers["X-Endpoint"] == "1"
      assert hydrated_context.base_url == "https://api.example.com"
      assert hydrated_context.retry_policies["default"]["max_attempts"] == 7
      assert Map.has_key?(hydrated_context.type_schemas, "SampleRequest")
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", _schema, _opts ->
      {:ok, %{"ok" => true}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, opts ->
      assert Keyword.get(opts, :max_attempts) == 7
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"ok" => true}} = Runtime.execute(manifest, "sample", payload, context)
  end

  test "build_context!/2 compiles manifest state once for generated clients" do
    manifest = %{
      name: "demo",
      version: "0.1.0",
      base_url: "https://api.example.com",
      retry_policies: %{"default" => %{max_attempts: 3}},
      endpoints: [%{id: "health", method: "GET", path: "/health"}],
      types: %{"Health" => %{fields: %{ok: %{type: "boolean", required: true}}}}
    }

    context = Runtime.build_context!(manifest, [])

    assert context.base_url == "https://api.example.com"
    assert context.retry_policies["default"]["max_attempts"] == 3
    assert Map.has_key?(context.type_schemas, "Health")
  end

  test "execute_endpoint/4 runs a direct endpoint without rebuilding a manifest" do
    endpoint = %Endpoint{
      id: "get_self",
      method: "GET",
      path: "/v1/users/me",
      headers: %{"X-Endpoint" => "1"},
      query: %{}
    }

    context = %Context{
      base_url: "https://api.example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "get_self", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, headers: headers},
                                             runtime_context ->
      assert url == "https://api.example.com/v1/users/me"
      assert headers["X-Endpoint"] == "1"
      assert runtime_context.base_url == "https://api.example.com"
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", _schema, _opts ->
      {:ok, %{"ok" => true}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"ok" => true}} =
             Runtime.execute_endpoint(endpoint, nil, context, body_type: "raw")
  end

  test "execute_request/3 runs a raw request spec through the shared endpoint pipeline" do
    request_spec = %{
      method: :get,
      path: "/v1/users/{id}",
      path_params: %{id: "user-123"},
      query: %{include: "workspace"},
      body: nil,
      form_data: nil,
      headers: %{"X-Request-Source" => "raw"},
      auth: "secret-token",
      security: nil,
      request_schema: nil,
      response_schema: nil,
      id: "raw.get_user"
    }

    context = %Context{
      base_url: "https://api.example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "raw.get_user", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, headers: headers},
                                             runtime_context ->
      assert url == "https://api.example.com/v1/users/user-123?include=workspace"
      assert headers["X-Request-Source"] == "raw"
      assert headers["Authorization"] == "Bearer secret-token"
      assert runtime_context.base_url == "https://api.example.com"
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", _schema, _opts ->
      {:ok, %{"ok" => true}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"ok" => true}} = Pristine.execute_request(request_spec, context)
  end

  test "execute_request/3 accepts generated OpenAPI request maps" do
    request =
      OpenAPIClient.request(%{
        args: %{},
        call: {Pristine.RuntimeTest.GeneratedClient, :get_user},
        method: :post,
        url: "/v1/users",
        opts: [],
        path_params: %{},
        query: %{},
        body: %{"name" => "Ada"},
        form_data: %{},
        auth: "secret-token",
        request: [{"application/json", :map}],
        response: [{200, :map}],
        security: [%{"bearerAuth" => []}]
      })

    assert {:ok, request} = request

    context = %Context{
      base_url: "https://api.example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }

    expect(Pristine.SerializerMock, :encode, fn %{"name" => "Ada"}, _opts ->
      {:ok, "{\"name\":\"Ada\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "Pristine.RuntimeTest.GeneratedClient.get_user",
                                                  fun,
                                                  _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, headers: headers, body: body},
                                             _runtime_context ->
      assert url == "https://api.example.com/v1/users"
      assert headers["Authorization"] == "Bearer secret-token"
      assert headers["content-type"] == "application/json"
      assert body == "{\"name\":\"Ada\"}"
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", _schema, _opts ->
      {:ok, %{"ok" => true}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"ok" => true}} = Runtime.execute_request(request, context)
  end

  test "execute_request/3 preserves path traversal validation for low-level specs" do
    request_spec = %{
      method: :get,
      path: "/v1/users/{id}",
      path_params: %{id: "../secret"},
      query: %{},
      body: nil,
      form_data: nil,
      headers: %{},
      auth: nil,
      security: nil,
      request_schema: nil,
      response_schema: nil,
      id: nil
    }

    context = %Context{
      base_url: "https://api.example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert_raise ArgumentError, ~r/path traversal/i, fn ->
      Runtime.execute_request(request_spec, context)
    end
  end
end
