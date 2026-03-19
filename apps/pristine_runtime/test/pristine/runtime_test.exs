defmodule Pristine.RequestExecutionTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, EndpointMetadata, Request, Response}
  alias Pristine.OpenAPI.Client, as: OpenAPIClient

  setup :set_mox_from_context
  setup :verify_on_exit!
  setup :capture_result_classifier_endpoint

  defmodule EndpointMetadataClassifier do
    def classify(result, endpoint, _context, _opts) do
      send(Process.get(:runtime_test_pid), {:classified_endpoint, endpoint, result})

      %{
        retry?: false,
        retry_after_ms: nil,
        breaker_outcome: :ignore,
        telemetry: %{classification: :success, breaker_outcome: :ignore}
      }
    end
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
        call: {__MODULE__.GeneratedClient, :get_user},
        method: :post,
        path_template: "/v1/users",
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

    expect(
      Pristine.CircuitBreakerMock,
      :call,
      fn "Pristine.RequestExecutionTest.GeneratedClient.get_user", fun, _opts ->
        fun.()
      end
    )

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

    assert {:ok, %{"ok" => true}} = Pristine.execute_request(request, context)
  end

  test "execute_request/3 classifies against manifest-free endpoint metadata" do
    request_spec = %{
      method: :get,
      path: "/v1/users/{id}",
      path_params: %{id: "user-123"},
      query: %{include: "workspace"},
      body: nil,
      form_data: nil,
      headers: %{"X-Request-Source" => "raw"},
      auth: "secret-token",
      security: [%{"bearerAuth" => []}],
      request_schema: nil,
      response_schema: nil,
      id: "raw.get_user",
      resource: "users",
      retry: "notion.read",
      rate_limit: "notion.integration",
      circuit_breaker: "core_api",
      telemetry: "request.users"
    }

    context = %Context{
      base_url: "https://api.example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock,
      result_classifier: EndpointMetadataClassifier
    }

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "core_api", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url}, _runtime_context ->
      assert url == "https://api.example.com/v1/users/user-123?include=workspace"
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", _schema, _opts ->
      {:ok, %{"ok" => true}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, opts ->
      assert Keyword.get(opts, :max_attempts) == nil
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"ok" => true}} = Pristine.execute_request(request_spec, context)

    assert_receive {:classified_endpoint, %EndpointMetadata{} = endpoint,
                    {:ok, %Response{status: 200}}}

    assert endpoint.id == "raw.get_user"
    assert endpoint.path == "/v1/users/{id}"
    assert endpoint.resource == "users"
    assert endpoint.retry == "notion.read"
    assert endpoint.rate_limit == "notion.integration"
    assert endpoint.circuit_breaker == "core_api"
    assert endpoint.security == [%{"bearerAuth" => []}]
    assert endpoint.telemetry == "request.users"
  end

  test "execute_request/3 rejects raw request specs that only provide url" do
    request_spec = %{
      method: :get,
      url: "/v1/users",
      path_params: %{},
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

    assert_raise ArgumentError, ~r/invalid request spec/, fn ->
      Pristine.execute_request(request_spec, context)
    end
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
      Pristine.execute_request(request_spec, context)
    end
  end

  defp capture_result_classifier_endpoint(_context) do
    Process.put(:runtime_test_pid, self())

    on_exit(fn ->
      Process.delete(:runtime_test_pid)
    end)

    :ok
  end
end
