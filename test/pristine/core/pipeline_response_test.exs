defmodule Pristine.Core.PipelineResponseTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Pipeline, Request, Response}
  alias Pristine.Error
  alias Pristine.Manifest

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "wraps non-2xx responses with Pristine.Error" do
    manifest = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{
          id: "ping",
          method: "POST",
          path: "/ping",
          request: "PingRequest",
          response: "PingResponse"
        }
      ],
      types: %{
        "PingRequest" => %{fields: %{prompt: %{type: "string", required: true}}},
        "PingResponse" => %{fields: %{ok: %{type: "boolean", required: true}}}
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

    payload = %{"prompt" => "hi"}

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{}, ^context ->
      {:ok, %Response{status: 429, body: "{\"error\":\"nope\"}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"error\":\"nope\"}", nil, _opts ->
      {:ok, %{"error" => "nope"}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:error, %Error{type: :rate_limit, status: 429, body: %{"error" => "nope"}}} =
             Pipeline.execute(manifest, "ping", payload, context)
  end

  test "preserves serializer errors for non-2xx responses" do
    manifest = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{
          id: "ping",
          method: "POST",
          path: "/ping",
          request: "PingRequest",
          response: "PingResponse"
        }
      ],
      types: %{
        "PingRequest" => %{fields: %{prompt: %{type: "string", required: true}}},
        "PingResponse" => %{fields: %{ok: %{type: "boolean", required: true}}}
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

    payload = %{"prompt" => "hi"}

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{}, ^context ->
      {:ok, %Response{status: 500, body: "bad"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "bad", nil, _opts ->
      {:error, :invalid_json}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:error, :invalid_json} = Pipeline.execute(manifest, "ping", payload, context)
  end

  test "unwraps responses before validation" do
    manifest = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{
          id: "ping",
          method: "POST",
          path: "/ping",
          request: "PingRequest",
          response: "PingResponse",
          response_unwrap: "data.result"
        }
      ],
      types: %{
        "PingRequest" => %{fields: %{prompt: %{type: "string", required: true}}},
        "PingResponse" => %{fields: %{ok: %{type: "boolean", required: true}}}
      }
    }

    {:ok, manifest} = Manifest.load(manifest)

    context = %Context{
      base_url: "https://example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      type_schemas: %{"PingResponse" => :string},
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }

    payload = %{"prompt" => "hi"}

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{}, ^context ->
      {:ok, %Response{status: 200, body: "{\"data\":{\"result\":\"ok\"}}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"data\":{\"result\":\"ok\"}}", nil, _opts ->
      {:ok, %{"data" => %{"result" => "ok"}}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, "ok"} = Pipeline.execute(manifest, "ping", payload, context)
  end
end
