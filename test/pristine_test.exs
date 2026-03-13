defmodule PristineTest do
  use ExUnit.Case
  doctest Pristine

  test "loads a manifest" do
    input = %{name: "demo", version: "0.1.0", endpoints: [], types: %{}}

    assert {:ok, manifest} = Pristine.load_manifest(input)
    assert manifest.name == "demo"
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
