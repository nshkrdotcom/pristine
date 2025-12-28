defmodule Pristine.Core.PipelineTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Pipeline, Request, Response}
  alias Pristine.Manifest

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "executes the request pipeline" do
    manifest = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{
          id: "sample",
          method: "POST",
          path: "/sampling",
          request: "SampleRequest",
          response: "SampleResponse",
          retry: "default"
        }
      ],
      types: %{
        "SampleRequest" => %{
          fields: %{
            prompt: %{type: "string", required: true},
            sampling_params: %{type: "string", required: true}
          }
        },
        "SampleResponse" => %{
          fields: %{
            text: %{type: "string", required: true}
          }
        }
      }
    }

    {:ok, manifest} = Manifest.load(manifest)

    context = %Context{
      base_url: "https://example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock
    }

    payload = %{"prompt" => "hi", "sampling_params" => "params"}

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, method: "POST"}, ^context ->
      assert url == "https://example.com/sampling"
      {:ok, %Response{status: 200, body: "{\"text\":\"hi\"}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"text\":\"hi\"}", _schema, _opts ->
      {:ok, %{"text" => "hi"}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"text" => "hi"}} = Pipeline.execute(manifest, "sample", payload, context)
  end

  test "applies auth, query, and path params" do
    manifest = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{
          id: "sample",
          method: "POST",
          path: "/sampling/:id",
          request: "SampleRequest",
          response: "SampleResponse",
          retry: "default"
        }
      ],
      types: %{
        "SampleRequest" => %{
          fields: %{
            prompt: %{type: "string", required: true},
            sampling_params: %{type: "string", required: true}
          }
        },
        "SampleResponse" => %{
          fields: %{
            text: %{type: "string", required: true}
          }
        }
      }
    }

    {:ok, manifest} = Manifest.load(manifest)

    context = %Context{
      base_url: "https://example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      auth: [{Pristine.AuthMock, [value: "secret"]}],
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }

    payload = %{"prompt" => "hi", "sampling_params" => "params"}

    expect(Pristine.AuthMock, :headers, fn _opts ->
      {:ok, %{"X-API-Key" => "secret"}}
    end)

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "sample", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, headers: headers}, ^context ->
      assert url == "https://example.com/sampling/abc?limit=10"
      assert headers["X-API-Key"] == "secret"
      {:ok, %Response{status: 200, body: "{\"text\":\"hi\"}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"text\":\"hi\"}", _schema, _opts ->
      {:ok, %{"text" => "hi"}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"text" => "hi"}} =
             Pipeline.execute(
               manifest,
               "sample",
               payload,
               context,
               path_params: %{id: "abc"},
               query: %{limit: 10}
             )
  end
end
