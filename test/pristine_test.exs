defmodule PristineTest do
  use ExUnit.Case
  doctest Pristine

  test "top-level API keeps the narrowed runtime boundary" do
    assert function_exported?(Pristine, :context, 1)
    assert function_exported?(Pristine, :foundation_context, 1)
    assert function_exported?(Pristine, :execute_request, 3)

    refute function_exported?(Pristine, :load_manifest, 1)
    refute function_exported?(Pristine, :load_manifest_file, 1)
    refute function_exported?(Pristine, :execute, 5)
    refute function_exported?(Pristine, :execute_endpoint, 4)
  end

  test "builds a Foundation-backed context via the public helper" do
    context =
      Pristine.foundation_context(
        base_url: "https://api.example.com",
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        rate_limit: false,
        circuit_breaker: false,
        telemetry: [namespace: [:demo_sdk]]
      )

    assert %Pristine.Core.Context{} = context
    assert context.retry == Pristine.Adapters.Retry.Foundation
    assert context.telemetry_events.request_stop == [:demo_sdk, :request, :stop]
  end
end
