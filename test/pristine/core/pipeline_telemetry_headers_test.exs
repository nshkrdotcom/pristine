defmodule Pristine.Core.PipelineTelemetryHeadersTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, EndpointMetadata, Pipeline, Request, Response}

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "injects telemetry headers" do
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

    expect(Pristine.TransportMock, :send, fn %Request{headers: headers}, ^context ->
      assert headers["X-Stainless-OS"]
      assert headers["X-Stainless-Arch"]
      assert headers["X-Stainless-Runtime"]
      assert headers["X-Stainless-Runtime-Version"]
      assert headers["x-stainless-retry-count"] == "2"
      assert headers["x-stainless-read-timeout"] == "5000"
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", _schema, _opts ->
      {:ok, %{"ok" => true}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute_endpoint(endpoint(), payload, context,
               retry_count: 2,
               timeout: 5_000
             )
  end

  defp endpoint do
    %EndpointMetadata{
      id: "ping",
      method: "POST",
      path: "/ping",
      headers: %{},
      query: %{}
    }
  end
end
