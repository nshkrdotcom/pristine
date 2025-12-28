defmodule Pristine.Core.StreamResponseTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.StreamResponse

  describe "struct" do
    test "has required fields" do
      stream = Stream.iterate(0, &(&1 + 1))

      response = %StreamResponse{
        stream: stream,
        status: 200,
        headers: %{"content-type" => "text/event-stream"}
      }

      assert response.status == 200
      assert response.headers["content-type"] == "text/event-stream"
      assert is_function(response.stream) or is_struct(response.stream, Stream)
    end

    test "metadata defaults to empty map" do
      response = %StreamResponse{
        stream: [],
        status: 200,
        headers: %{}
      }

      assert response.metadata == %{}
    end

    test "can include custom metadata" do
      response = %StreamResponse{
        stream: [],
        status: 200,
        headers: %{},
        metadata: %{request_id: "req_123", elapsed_ms: 50}
      }

      assert response.metadata.request_id == "req_123"
      assert response.metadata.elapsed_ms == 50
    end
  end

  describe "stream field" do
    test "can be enumerated" do
      events = [1, 2, 3]

      response = %StreamResponse{
        stream: events,
        status: 200,
        headers: %{}
      }

      assert Enum.to_list(response.stream) == [1, 2, 3]
    end

    test "can be a lazy stream" do
      counter = :counters.new(1, [:atomics])

      stream =
        Stream.repeatedly(fn ->
          :counters.add(counter, 1, 1)
          :counters.get(counter, 1)
        end)

      response = %StreamResponse{
        stream: stream,
        status: 200,
        headers: %{}
      }

      # Take only 3 items - should only increment counter 3 times
      result = Enum.take(response.stream, 3)
      assert result == [1, 2, 3]
      assert :counters.get(counter, 1) == 3
    end
  end
end
