defmodule PristineTest do
  use ExUnit.Case, async: true
  doctest Pristine

  test "top-level API keeps the rebuilt runtime boundary" do
    assert function_exported?(Pristine, :execute, 3)
    assert function_exported?(Pristine, :stream, 3)

    refute function_exported?(Pristine, :context, 1)
    refute function_exported?(Pristine, :foundation_context, 1)
    refute function_exported?(Pristine, :execute_request, 3)
  end

  test "builds a Foundation-backed client via the public helper" do
    client =
      Pristine.Client.foundation(
        base_url: "https://api.example.com",
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        rate_limit: false,
        circuit_breaker: false,
        telemetry: false
      )

    assert %Pristine.Client{} = client
    assert %Pristine.Core.Context{} = client.context
    assert client.base_url == "https://api.example.com"
    assert client.transport == Pristine.TransportMock
    assert client.default_headers == %{}
    assert client.default_auth == []
    assert client.runtime_defaults.retry == Pristine.Adapters.Retry.Foundation
  end
end
