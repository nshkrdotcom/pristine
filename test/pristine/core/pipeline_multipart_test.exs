defmodule Pristine.Core.PipelineMultipartTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Pipeline, Request, Response}
  alias Pristine.Manifest

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "encodes multipart payloads" do
    manifest = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{
          id: "upload",
          method: "POST",
          path: "/upload",
          request: "UploadRequest",
          response: "UploadResponse",
          body_type: "multipart"
        }
      ],
      types: %{
        "UploadRequest" => %{
          fields: %{
            file: %{type: "string", required: true}
          }
        },
        "UploadResponse" => %{
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
      multipart: Pristine.MultipartMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.Adapters.CircuitBreaker.Noop
    }

    payload = %{file: "hello"}

    expect(Pristine.MultipartMock, :encode, fn ^payload, _opts ->
      {"multipart/form-data; boundary=abc", "--abc"}
    end)

    expect(Pristine.TransportMock, :send, fn %Request{headers: headers}, ^context ->
      assert headers["content-type"] == "multipart/form-data; boundary=abc"
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

    assert {:ok, %{"ok" => true}} = Pipeline.execute(manifest, "upload", payload, context)
  end
end
