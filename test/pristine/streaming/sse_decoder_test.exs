defmodule Pristine.Streaming.SSEDecoderTest do
  use ExUnit.Case, async: true

  alias Pristine.Streaming.{Event, SSEDecoder}

  describe "new/0" do
    test "creates empty decoder with empty buffer" do
      decoder = SSEDecoder.new()
      assert decoder.buffer == ""
    end
  end

  describe "feed/2" do
    test "parses complete single event" do
      decoder = SSEDecoder.new()
      chunk = "event: message\ndata: {\"foo\":\"bar\"}\n\n"

      {events, _new_decoder} = SSEDecoder.feed(decoder, chunk)

      assert [%Event{event: "message", data: ~s({"foo":"bar"})}] = events
    end

    test "handles chunked delivery" do
      decoder = SSEDecoder.new()

      # First chunk - incomplete
      {events1, decoder1} = SSEDecoder.feed(decoder, "data: par")
      assert events1 == []

      # Second chunk - completes the event
      {events2, _decoder2} = SSEDecoder.feed(decoder1, "tial\n\n")
      assert [%Event{data: "partial"}] = events2
    end

    test "parses multiple events in single chunk" do
      decoder = SSEDecoder.new()
      chunk = "data: first\n\ndata: second\n\n"

      {events, _decoder} = SSEDecoder.feed(decoder, chunk)

      assert [%Event{data: "first"}, %Event{data: "second"}] = events
    end

    test "handles multi-line data" do
      decoder = SSEDecoder.new()
      chunk = "data: line1\ndata: line2\ndata: line3\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "line1\nline2\nline3"
    end

    test "parses event type" do
      decoder = SSEDecoder.new()
      chunk = "event: custom_type\ndata: payload\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.event == "custom_type"
      assert event.data == "payload"
    end

    test "parses event id" do
      decoder = SSEDecoder.new()
      chunk = "id: evt_123\ndata: payload\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.id == "evt_123"
    end

    test "parses retry interval" do
      decoder = SSEDecoder.new()
      chunk = "retry: 5000\ndata: payload\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.retry == 5000
    end

    test "ignores comment lines" do
      decoder = SSEDecoder.new()
      chunk = ": this is a comment\ndata: actual_data\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "actual_data"
    end

    test "handles \\r\\n line endings" do
      decoder = SSEDecoder.new()
      chunk = "data: test\r\n\r\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "test"
    end

    test "handles \\r line endings" do
      decoder = SSEDecoder.new()
      chunk = "data: test\r\r"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "test"
    end

    test "handles mixed line endings" do
      decoder = SSEDecoder.new()
      chunk = "event: test\r\ndata: mixed\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.event == "test"
      assert event.data == "mixed"
    end

    test "second event without ID does not inherit from first" do
      decoder = SSEDecoder.new()

      # First event sets ID
      {[event1], decoder1} = SSEDecoder.feed(decoder, "id: 1\ndata: first\n\n")
      assert event1.id == "1"

      # Second event without ID should NOT inherit (per SSE spec, id is per-event)
      {[event2], _decoder2} = SSEDecoder.feed(decoder1, "data: second\n\n")
      assert event2.id == nil
    end

    test "ignores invalid retry values" do
      decoder = SSEDecoder.new()
      chunk = "retry: not_a_number\ndata: test\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.retry == nil
      assert event.data == "test"
    end

    test "handles empty data field" do
      decoder = SSEDecoder.new()
      chunk = "event: ping\ndata:\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.event == "ping"
      assert event.data == ""
    end

    test "handles field without colon space" do
      decoder = SSEDecoder.new()
      chunk = "data:no_space\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "no_space"
    end

    test "returns remaining buffer for incomplete events" do
      decoder = SSEDecoder.new()
      chunk = "data: incomplete"

      {events, new_decoder} = SSEDecoder.feed(decoder, chunk)

      assert events == []
      assert new_decoder.buffer =~ "incomplete"
    end

    test "handles empty chunk" do
      decoder = SSEDecoder.new()
      {events, _decoder} = SSEDecoder.feed(decoder, "")
      assert events == []
    end

    test "handles only whitespace chunk" do
      decoder = SSEDecoder.new()
      {events, _decoder} = SSEDecoder.feed(decoder, "   \n\n")
      # Empty event block
      assert length(events) == 1
      assert hd(events).data == ""
    end

    test "handles all fields in one event" do
      decoder = SSEDecoder.new()
      chunk = "event: update\nid: evt_456\nretry: 3000\ndata: payload\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.event == "update"
      assert event.id == "evt_456"
      assert event.retry == 3000
      assert event.data == "payload"
    end

    test "handles BOM in data - BOM prefixes field name so line is ignored" do
      decoder = SSEDecoder.new()
      # UTF-8 BOM followed by data - BOM becomes part of the field name
      # which won't match "data", so the line is effectively ignored
      chunk = "\uFEFFdata: test\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      # The BOM-prefixed field name doesn't match "data", so it's ignored
      # Per SSE spec, unknown fields are silently ignored
      assert event.data == ""
    end

    test "handles BOM on its own line before data" do
      decoder = SSEDecoder.new()
      # BOM on its own line, then data on next line
      chunk = "\uFEFF\ndata: test\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "test"
    end

    test "handles multiple data lines with empty lines between" do
      decoder = SSEDecoder.new()
      chunk = "data: line1\ndata:\ndata: line3\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "line1\n\nline3"
    end

    test "parses retry with trailing garbage as just the integer part" do
      decoder = SSEDecoder.new()
      chunk = "retry: 5000abc\ndata: test\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      # Integer.parse returns {5000, "abc"}, so we take the integer
      assert event.retry == 5000
    end
  end

  describe "decode_stream/1" do
    test "creates stream from enumerable of chunks" do
      chunks = ["data: one\n\n", "data: two\n\n"]

      events =
        chunks
        |> SSEDecoder.decode_stream()
        |> Enum.to_list()

      assert [%Event{data: "one"}, %Event{data: "two"}] = events
    end

    test "handles chunked data across stream" do
      chunks = ["data: spl", "it_data\n\n"]

      events =
        chunks
        |> SSEDecoder.decode_stream()
        |> Enum.to_list()

      assert [%Event{data: "split_data"}] = events
    end

    test "handles empty stream" do
      chunks = []

      events =
        chunks
        |> SSEDecoder.decode_stream()
        |> Enum.to_list()

      assert events == []
    end

    test "handles stream with no complete events" do
      chunks = ["data: incomplete"]

      events =
        chunks
        |> SSEDecoder.decode_stream()
        |> Enum.to_list()

      assert events == []
    end

    test "handles complex multi-chunk scenario" do
      chunks = [
        "event: start\ndata: first",
        "\n\nevent: middle\n",
        "data: second\n\ndata: third\n\n"
      ]

      events =
        chunks
        |> SSEDecoder.decode_stream()
        |> Enum.to_list()

      assert length(events) == 3
      assert Enum.at(events, 0).event == "start"
      assert Enum.at(events, 0).data == "first"
      assert Enum.at(events, 1).event == "middle"
      assert Enum.at(events, 1).data == "second"
      assert Enum.at(events, 2).data == "third"
    end

    test "works with Stream.map" do
      chunks = ["data: {\"n\":1}\n\n", "data: {\"n\":2}\n\n"]

      results =
        chunks
        |> SSEDecoder.decode_stream()
        |> Stream.map(&Event.json!/1)
        |> Enum.to_list()

      assert [%{"n" => 1}, %{"n" => 2}] = results
    end
  end
end
