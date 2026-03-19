defmodule Pristine.TransportBoundaryTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Transport.{Finch, FinchStream}

  test "active runtime transport uses the supported transport ports only" do
    assert Code.ensure_loaded?(Pristine.Ports.Transport)
    assert Code.ensure_loaded?(Pristine.Ports.StreamTransport)
    refute Code.ensure_loaded?(Pristine.Ports.HTTPTransport)

    assert Code.ensure_loaded?(Finch)
    assert Code.ensure_loaded?(FinchStream)
    assert function_exported?(Finch, :send, 2)
    assert function_exported?(FinchStream, :stream, 2)
    refute function_exported?(Finch, :request, 5)
    refute function_exported?(Finch, :stream, 5)
  end
end
