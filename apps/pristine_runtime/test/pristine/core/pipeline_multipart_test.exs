defmodule Pristine.Core.PipelineMultipartTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Pipeline, Request, Response}
  alias Pristine.Operation

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "encodes multipart payloads from rendered operations" do
    operation =
      Operation.new(%{
        id: "upload",
        method: :post,
        path_template: "/upload",
        form_data: %{file: "hello"},
        request_schema: nil,
        response_schemas: %{200 => nil}
      })

    context = %Context{
      base_url: "https://example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      multipart: Pristine.MultipartMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.Adapters.CircuitBreaker.Noop
    }

    expect(Pristine.MultipartMock, :encode, fn %{file: "hello"}, _opts ->
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

    assert {:ok, %{"ok" => true}} = Pipeline.execute_operation(operation, context)
  end
end
