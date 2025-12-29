defmodule Pristine.Core.PipelineRetryIdempotencyTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Pipeline, Request, Response}
  alias Pristine.Manifest

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "reuses idempotency key across retries" do
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
          idempotency: true
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
      idempotency_header: "X-Idempotency-Key",
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }

    payload = %{"prompt" => "hi"}

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, 2, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, 2, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, 2, fn %Request{headers: headers}, ^context ->
      key = headers["X-Idempotency-Key"]

      case Process.get(:idempotency_key) do
        nil -> Process.put(:idempotency_key, key)
        existing -> assert key == existing
      end

      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", nil, _opts ->
      {:ok, %{"ok" => true}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, opts ->
      before_attempt = Keyword.get(opts, :before_attempt, fn _ -> :ok end)
      before_attempt.(0)
      _ = fun.()
      before_attempt.(1)
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"ok" => true}} = Pipeline.execute(manifest, "ping", payload, context)
  end
end
