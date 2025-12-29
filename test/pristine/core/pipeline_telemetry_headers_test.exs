defmodule Pristine.Core.PipelineTelemetryHeadersTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Pipeline, Request, Response}
  alias Pristine.Manifest

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "injects telemetry headers" do
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
        "PingRequest" => %{
          fields: %{
            prompt: %{type: "string", required: true}
          }
        },
        "PingResponse" => %{
          fields: %{
            ok: %{type: "boolean", required: true}
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

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute(manifest, "ping", payload, context,
               retry_count: 2,
               timeout: 5_000
             )
  end
end
