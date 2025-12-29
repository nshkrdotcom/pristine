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

  describe "dispatch helpers" do
    defmodule Handler do
      def on_message_start(payload), do: {:message_start, payload}
      def on_content_block_start(payload), do: {:content_block_start, payload}
      def on_content_block_delta(payload), do: {:content_block_delta, payload}
      def on_content_block_stop(payload), do: {:content_block_stop, payload}
      def on_message_stop(payload), do: {:message_stop, payload}
      def on_error(payload), do: {:error, payload}
      def on_unknown(event, data), do: {:unknown, event, data}
    end

    test "dispatch_event routes by event type" do
      event = %Pristine.Streaming.Event{event: "message_start", data: ~s({"ok":true})}
      assert StreamResponse.dispatch_event(event, Handler) == {:message_start, %{"ok" => true}}
    end

    test "dispatch_event falls back to on_unknown" do
      event = %Pristine.Streaming.Event{event: "custom", data: ~s({"raw":true})}

      assert StreamResponse.dispatch_event(event, Handler) ==
               {:unknown, "custom", ~s({"raw":true})}
    end

    test "dispatch_stream maps events through handler" do
      events = [
        %Pristine.Streaming.Event{event: "message_stop", data: ~s({"n":1})},
        %Pristine.Streaming.Event{event: "error", data: ~s({"n":2})}
      ]

      response = %StreamResponse{
        stream: events,
        status: 200,
        headers: %{}
      }

      assert StreamResponse.dispatch_stream(response, Handler) |> Enum.to_list() == [
               {:message_stop, %{"n" => 1}},
               {:error, %{"n" => 2}}
             ]
    end

    test "cancel calls metadata cancel function when present" do
      called = self()

      response = %StreamResponse{
        stream: [],
        status: 200,
        headers: %{},
        metadata: %{
          cancel: fn -> send(called, :cancelled) end
        }
      }

      assert :ok == StreamResponse.cancel(response)
      assert_received :cancelled
    end

    test "last_event_id reads from agent when present" do
      {:ok, ref} = Agent.start_link(fn -> "evt_123" end)

      response = %StreamResponse{
        stream: [],
        status: 200,
        headers: %{},
        metadata: %{last_event_id_ref: ref}
      }

      assert StreamResponse.last_event_id(response) == "evt_123"
      Agent.stop(ref)
    end
  end
end
