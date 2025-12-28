defmodule Pristine.Core.PipelineStreamTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Pipeline, StreamResponse}
  alias Pristine.Manifest
  alias Pristine.Streaming.Event

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "execute_stream/5" do
    test "executes streaming endpoint and returns StreamResponse" do
      manifest = build_manifest()
      {:ok, manifest} = Manifest.load(manifest)

      events = [
        %Event{event: "message", data: ~s({"n": 1})},
        %Event{event: "message", data: ~s({"n": 2})}
      ]

      expect(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"prompt":"test"})}
      end)

      expect(Pristine.StreamTransportMock, :stream, fn request, _context ->
        assert request.method == "POST"
        assert request.url =~ "/sample_stream"

        {:ok,
         %StreamResponse{
           stream: events,
           status: 200,
           headers: %{"content-type" => "text/event-stream"}
         }}
      end)

      expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas -> :ok end)

      context = build_context()
      payload = %{"prompt" => "test"}

      assert {:ok, %StreamResponse{} = response} =
               Pipeline.execute_stream(manifest, "sample_stream", payload, context)

      assert response.status == 200
      assert Enum.to_list(response.stream) == events
    end

    test "returns error when stream transport fails" do
      manifest = build_manifest()
      {:ok, manifest} = Manifest.load(manifest)

      expect(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"prompt":"test"})}
      end)

      expect(Pristine.StreamTransportMock, :stream, fn _request, _context ->
        {:error, :connection_failed}
      end)

      expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas -> :ok end)

      context = build_context()
      payload = %{"prompt" => "test"}

      assert {:error, :connection_failed} =
               Pipeline.execute_stream(manifest, "sample_stream", payload, context)
    end

    test "raises when stream_transport is not configured" do
      manifest = build_manifest()
      {:ok, manifest} = Manifest.load(manifest)

      context = %Context{
        base_url: "https://example.com",
        serializer: Pristine.SerializerMock,
        telemetry: Pristine.TelemetryMock
        # stream_transport is nil
      }

      # These might or might not be called depending on when the error is raised
      stub(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"prompt":"test"})}
      end)

      stub(Pristine.TelemetryMock, :emit, fn _event, _meta, _meas -> :ok end)

      assert_raise ArgumentError, ~r/stream_transport is required/, fn ->
        Pipeline.execute_stream(manifest, "sample_stream", %{}, context)
      end
    end
  end

  describe "execute_future/5" do
    test "executes request and starts polling" do
      manifest = build_manifest()
      {:ok, manifest} = Manifest.load(manifest)

      expect(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"prompt":"test"})}
      end)

      expect(Pristine.CircuitBreakerMock, :call, fn _name, fun, _opts -> fun.() end)

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        {:ok,
         %Pristine.Core.Response{
           status: 200,
           body: ~s({"request_id": "req_123"})
         }}
      end)

      expect(Pristine.SerializerMock, :decode, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      expect(Pristine.RetryMock, :with_retry, fn fun, _opts -> fun.() end)
      expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas -> :ok end)

      expect(Pristine.FutureMock, :poll, fn request_id, _context, _opts ->
        assert request_id == "req_123"
        {:ok, Task.async(fn -> {:ok, %{"result" => "done"}} end)}
      end)

      context = build_future_context()
      payload = %{"prompt" => "test"}

      assert {:ok, task} = Pipeline.execute_future(manifest, "sample", payload, context)
      assert {:ok, %{"result" => "done"}} = Task.await(task, 5_000)
    end

    test "returns immediate response when no request_id" do
      manifest = build_manifest()
      {:ok, manifest} = Manifest.load(manifest)

      expect(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"prompt":"test"})}
      end)

      expect(Pristine.CircuitBreakerMock, :call, fn _name, fun, _opts -> fun.() end)

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        {:ok,
         %Pristine.Core.Response{
           status: 200,
           body: ~s({"result": "immediate"})
         }}
      end)

      expect(Pristine.SerializerMock, :decode, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      expect(Pristine.RetryMock, :with_retry, fn fun, _opts -> fun.() end)
      expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas -> :ok end)

      context = build_future_context()
      payload = %{"prompt" => "test"}

      assert {:ok, task} = Pipeline.execute_future(manifest, "sample", payload, context)
      assert {:ok, %{"result" => "immediate"}} = Task.await(task, 5_000)
    end

    test "returns error when initial request fails" do
      manifest = build_manifest()
      {:ok, manifest} = Manifest.load(manifest)

      expect(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"prompt":"test"})}
      end)

      expect(Pristine.CircuitBreakerMock, :call, fn _name, fun, _opts -> fun.() end)

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        {:error, :connection_refused}
      end)

      expect(Pristine.RetryMock, :with_retry, fn fun, _opts -> fun.() end)
      expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas -> :ok end)

      context = build_future_context()
      payload = %{"prompt" => "test"}

      assert {:error, :connection_refused} =
               Pipeline.execute_future(manifest, "sample", payload, context)
    end
  end

  defp build_manifest do
    %{
      name: "test",
      version: "1.0.0",
      endpoints: [
        %{
          id: "sample",
          method: "POST",
          path: "/sample",
          request: "SampleRequest",
          response: "SampleResponse"
        },
        %{
          id: "sample_stream",
          method: "POST",
          path: "/sample_stream",
          request: "SampleRequest",
          response: "SampleStreamResponse"
        }
      ],
      types: %{
        "SampleRequest" => %{
          fields: %{
            prompt: %{type: "string", required: true}
          }
        },
        "SampleResponse" => %{
          fields: %{
            text: %{type: "string"}
          }
        },
        "SampleStreamResponse" => %{
          fields: %{
            text: %{type: "string"}
          }
        }
      }
    }
  end

  defp build_context do
    %Context{
      base_url: "https://example.com",
      transport: Pristine.TransportMock,
      stream_transport: Pristine.StreamTransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock
    }
  end

  defp build_future_context do
    %Context{
      base_url: "https://example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      circuit_breaker: Pristine.CircuitBreakerMock,
      telemetry: Pristine.TelemetryMock,
      future: Pristine.FutureMock
    }
  end
end
