defmodule Tinkex.Streaming.SSEDecoderTest do
  use ExUnit.Case, async: true

  alias Tinkex.Streaming.SSEDecoder
  alias Tinkex.Streaming.ServerSentEvent

  describe "new/0" do
    test "creates empty decoder" do
      decoder = SSEDecoder.new()
      assert %SSEDecoder{buffer: ""} = decoder
    end
  end

  describe "feed/2" do
    test "parses single complete event" do
      decoder = SSEDecoder.new()
      {events, decoder} = SSEDecoder.feed(decoder, "data: hello\n\n")

      assert length(events) == 1
      assert [%ServerSentEvent{data: "hello"}] = events
      assert decoder.buffer == ""
    end

    test "parses event with type" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "event: message\ndata: hello\n\n")

      assert [%ServerSentEvent{event: "message", data: "hello"}] = events
    end

    test "parses event with id" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "id: 123\ndata: hello\n\n")

      assert [%ServerSentEvent{id: "123", data: "hello"}] = events
    end

    test "parses event with retry" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "retry: 5000\ndata: hello\n\n")

      assert [%ServerSentEvent{retry: 5000, data: "hello"}] = events
    end

    test "parses multiline data" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "data: line1\ndata: line2\ndata: line3\n\n")

      assert [%ServerSentEvent{data: "line1\nline2\nline3"}] = events
    end

    test "handles incomplete event" do
      decoder = SSEDecoder.new()
      {events, decoder} = SSEDecoder.feed(decoder, "data: partial")

      assert events == []
      assert decoder.buffer == "data: partial"
    end

    test "buffers partial and completes on next feed" do
      decoder = SSEDecoder.new()
      {events, decoder} = SSEDecoder.feed(decoder, "data: hel")
      assert events == []

      {events, decoder} = SSEDecoder.feed(decoder, "lo\n\n")
      assert [%ServerSentEvent{data: "hello"}] = events
      assert decoder.buffer == ""
    end

    test "parses multiple events in one chunk" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "data: first\n\ndata: second\n\n")

      assert length(events) == 2
      assert [%ServerSentEvent{data: "first"}, %ServerSentEvent{data: "second"}] = events
    end

    test "ignores comment lines" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, ": this is a comment\ndata: hello\n\n")

      assert [%ServerSentEvent{data: "hello"}] = events
    end

    test "handles CRLF line endings" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "data: hello\r\n\r\n")

      assert [%ServerSentEvent{data: "hello"}] = events
    end

    test "handles CR line endings" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "data: hello\r\r")

      assert [%ServerSentEvent{data: "hello"}] = events
    end

    test "handles empty data field" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "data:\n\n")

      assert [%ServerSentEvent{data: ""}] = events
    end

    test "handles unknown fields gracefully" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "unknown: value\ndata: hello\n\n")

      assert [%ServerSentEvent{data: "hello"}] = events
    end

    test "handles invalid retry value" do
      decoder = SSEDecoder.new()
      {events, _} = SSEDecoder.feed(decoder, "retry: invalid\ndata: hello\n\n")

      assert [%ServerSentEvent{retry: nil, data: "hello"}] = events
    end

    test "handles JSON data" do
      decoder = SSEDecoder.new()
      json_data = ~s({"key": "value"})
      {events, _} = SSEDecoder.feed(decoder, "data: #{json_data}\n\n")

      assert [%ServerSentEvent{data: ^json_data}] = events
    end
  end

  describe "buffer/1" do
    test "returns empty string for new decoder" do
      decoder = SSEDecoder.new()
      assert SSEDecoder.buffer(decoder) == ""
    end

    test "returns buffered data" do
      decoder = SSEDecoder.new()
      {_, decoder} = SSEDecoder.feed(decoder, "data: partial")
      assert SSEDecoder.buffer(decoder) == "data: partial"
    end
  end

  describe "has_pending?/1" do
    test "returns false for empty buffer" do
      decoder = SSEDecoder.new()
      refute SSEDecoder.has_pending?(decoder)
    end

    test "returns true when data is buffered" do
      decoder = SSEDecoder.new()
      {_, decoder} = SSEDecoder.feed(decoder, "data: partial")
      assert SSEDecoder.has_pending?(decoder)
    end
  end

  describe "ServerSentEvent.json/1" do
    test "decodes valid JSON data" do
      event = %ServerSentEvent{data: ~s({"key": "value"})}
      assert ServerSentEvent.json(event) == %{"key" => "value"}
    end

    test "returns raw string for invalid JSON" do
      event = %ServerSentEvent{data: "not json"}
      assert ServerSentEvent.json(event) == "not json"
    end

    test "decodes JSON array" do
      event = %ServerSentEvent{data: ~s([1, 2, 3])}
      assert ServerSentEvent.json(event) == [1, 2, 3]
    end

    test "decodes nested JSON" do
      event = %ServerSentEvent{data: ~s({"nested": {"key": "value"}})}
      assert ServerSentEvent.json(event) == %{"nested" => %{"key" => "value"}}
    end
  end
end
