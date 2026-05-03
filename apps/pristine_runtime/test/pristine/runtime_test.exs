defmodule Pristine.RequestExecutionTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Adapters.Auth.{Basic, Bearer}
  alias Pristine.Core.{EndpointMetadata, Request, Response, StreamResponse}
  alias Pristine.Streaming.Event

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

  test "execute/3 runs a rendered operation through the public runtime contract" do
    operation =
      Pristine.Operation.new(%{
        id: "users.get",
        method: :get,
        path_template: "/v1/users/{id}",
        path_params: %{id: "user-123"},
        query: %{include: "workspace"},
        headers: %{"X-Request-Source" => "rendered"},
        body: nil,
        form_data: nil,
        request_schema: nil,
        response_schemas: %{200 => nil},
        auth: %{
          use_client_default?: true,
          override: nil,
          security_schemes: ["bearerAuth"]
        },
        runtime: %{
          resource: "users",
          retry_group: "users.read",
          circuit_breaker: "users_api",
          rate_limit_group: "users.integration",
          telemetry_event: [:demo_sdk, :users, :get],
          timeout_ms: nil
        }
      })

    client =
      Pristine.Client.new(
        base_url: "https://api.example.com",
        default_headers: %{"X-Client" => "demo"},
        default_auth: [Bearer.new("secret-token")],
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        retry: Pristine.RetryMock,
        telemetry: Pristine.TelemetryMock,
        circuit_breaker: Pristine.CircuitBreakerMock,
        rate_limiter: Pristine.RateLimitMock
      )

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "users_api", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, headers: headers},
                                             runtime_context ->
      assert url == "https://api.example.com/v1/users/user-123?include=workspace"
      assert headers["X-Client"] == "demo"
      assert headers["X-Request-Source"] == "rendered"
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

    assert {:ok, %{"ok" => true}} = Pristine.execute(client, operation)
  end

  test "execute/3 supports request auth overrides without using client defaults" do
    operation =
      Pristine.Operation.new(%{
        id: "oauth.token",
        method: :post,
        path_template: "/v1/oauth/token",
        body: %{"code" => "secret", "grant_type" => "authorization_code"},
        request_schema: nil,
        response_schemas: %{200 => nil},
        auth: %{
          use_client_default?: false,
          override: [Basic.new("client-id", "client-secret")],
          security_schemes: ["basicAuth"]
        },
        runtime: %{
          resource: "oauth_control",
          retry_group: "oauth.control",
          circuit_breaker: "oauth_api",
          rate_limit_group: "oauth.integration",
          telemetry_event: [:demo_sdk, :oauth, :token],
          timeout_ms: nil
        }
      })

    client =
      Pristine.Client.new(
        base_url: "https://api.example.com",
        default_auth: [Bearer.new("secret-token")],
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        retry: Pristine.RetryMock,
        telemetry: Pristine.TelemetryMock,
        circuit_breaker: Pristine.CircuitBreakerMock,
        rate_limiter: Pristine.RateLimitMock
      )

    expect(Pristine.SerializerMock, :encode, fn %{"code" => "secret", "grant_type" => _}, _opts ->
      {:ok, "{\"ok\":true}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "oauth_api", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{headers: headers}, _runtime_context ->
      assert headers["Authorization"] =~ "Basic "
      refute headers["Authorization"] == "Bearer secret-token"
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

    assert {:ok, %{"ok" => true}} = Pristine.execute(client, operation)
  end

  test "execute/3 classifies against metadata rendered from Pristine.Operation" do
    operation =
      Pristine.Operation.new(%{
        id: "users.get",
        method: :get,
        path_template: "/v1/users/{id}",
        path_params: %{id: "user-123"},
        query: %{include: "workspace"},
        headers: %{"X-Request-Source" => "rendered"},
        body: nil,
        form_data: nil,
        request_schema: nil,
        response_schemas: %{200 => nil},
        auth: %{
          use_client_default?: true,
          override: nil,
          security_schemes: ["bearerAuth"]
        },
        runtime: %{
          resource: "users",
          retry_group: "users.read",
          circuit_breaker: "core_api",
          rate_limit_group: "users.integration",
          telemetry_event: [:demo_sdk, :users, :get],
          timeout_ms: nil
        }
      })

    client =
      Pristine.Client.new(
        base_url: "https://api.example.com",
        default_auth: [Bearer.new("secret-token")],
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        retry: Pristine.RetryMock,
        telemetry: Pristine.TelemetryMock,
        circuit_breaker: Pristine.CircuitBreakerMock,
        rate_limiter: Pristine.RateLimitMock,
        result_classifier: EndpointMetadataClassifier
      )

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

    assert {:ok, %{"ok" => true}} = Pristine.execute(client, operation)

    assert_receive {:classified_endpoint, %EndpointMetadata{} = endpoint,
                    {:ok, %Response{status: 200}}}

    assert endpoint.id == "users.get"
    assert endpoint.path == "/v1/users/{id}"
    assert endpoint.resource == "users"
    assert endpoint.retry == "users.read"
    assert endpoint.rate_limit == "users.integration"
    assert endpoint.circuit_breaker == "core_api"
    assert endpoint.security == [%{"bearerAuth" => []}]
    assert endpoint.telemetry == [:demo_sdk, :users, :get]
  end

  test "execute/3 preserves path traversal validation for rendered operations" do
    operation =
      Pristine.Operation.new(%{
        id: "users.get",
        method: :get,
        path_template: "/v1/users/{id}",
        path_params: %{id: "../secret"},
        request_schema: nil,
        response_schemas: %{200 => nil}
      })

    client =
      Pristine.Client.new(
        base_url: "https://api.example.com",
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        retry: Pristine.RetryMock,
        telemetry: Pristine.TelemetryMock,
        circuit_breaker: Pristine.CircuitBreakerMock,
        rate_limiter: Pristine.RateLimitMock
      )

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    error =
      assert_raise ArgumentError, fn ->
        Pristine.execute(client, operation)
      end

    assert error.message |> String.downcase() |> String.contains?("path traversal")
  end

  test "stream/3 uses the public client and operation contract" do
    operation =
      Pristine.Operation.new(%{
        id: "events.stream",
        method: :get,
        path_template: "/v1/events",
        headers: %{"accept" => "text/event-stream"},
        auth: %{
          use_client_default?: true,
          override: nil,
          security_schemes: ["bearerAuth"]
        },
        runtime: %{
          resource: "events",
          retry_group: "events.read",
          circuit_breaker: "events_api",
          rate_limit_group: "events.integration",
          telemetry_event: [:demo_sdk, :events, :stream],
          timeout_ms: nil
        }
      })

    client =
      Pristine.Client.new(
        base_url: "https://api.example.com",
        default_auth: [Bearer.new("secret-token")],
        stream_transport: Pristine.StreamTransportMock,
        serializer: Pristine.SerializerMock
      )

    expect(Pristine.StreamTransportMock, :stream, fn %Request{url: url, headers: headers},
                                                     runtime_context ->
      assert url == "https://api.example.com/v1/events"
      assert headers["accept"] == "text/event-stream"
      assert headers["Authorization"] == "Bearer secret-token"
      assert runtime_context.base_url == "https://api.example.com"

      {:ok,
       %StreamResponse{
         stream: [%Event{event: "message", data: "{\"ok\":true}"}],
         status: 200,
         headers: %{"content-type" => "text/event-stream"},
         metadata: %{request_id: "req-123"}
       }}
    end)

    assert {:ok, %Pristine.Response{} = response} = Pristine.stream(client, operation)
    assert response.status == 200
    assert response.headers["content-type"] == "text/event-stream"
    assert response.metadata.request_id == "req-123"
    assert Enum.to_list(response.stream) == [%Event{event: "message", data: "{\"ok\":true}"}]
  end

  defp capture_result_classifier_endpoint(_context) do
    Process.put(:runtime_test_pid, self())

    on_exit(fn ->
      Process.delete(:runtime_test_pid)
    end)

    :ok
  end
end
