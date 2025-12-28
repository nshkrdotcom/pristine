defmodule Pristine.Streaming.EventTest do
  use ExUnit.Case, async: true

  alias Pristine.Streaming.Event

  describe "struct" do
    test "has event, data, id, and retry fields" do
      event = %Event{
        event: "message",
        data: ~s({"foo": "bar"}),
        id: "123",
        retry: 5000
      }

      assert event.event == "message"
      assert event.data == ~s({"foo": "bar"})
      assert event.id == "123"
      assert event.retry == 5000
    end

    test "fields default to nil" do
      event = %Event{}
      assert is_nil(event.event)
      assert is_nil(event.data)
      assert is_nil(event.id)
      assert is_nil(event.retry)
    end
  end

  describe "json/1" do
    test "parses JSON data field" do
      event = %Event{data: ~s({"name": "test", "value": 42})}

      assert {:ok, parsed} = Event.json(event)
      assert parsed["name"] == "test"
      assert parsed["value"] == 42
    end

    test "returns error for invalid JSON" do
      event = %Event{data: "not json"}

      assert {:error, _} = Event.json(event)
    end

    test "returns error for nil data" do
      event = %Event{data: nil}

      assert {:error, :no_data} = Event.json(event)
    end

    test "handles empty string data" do
      event = %Event{data: ""}

      assert {:error, :empty_data} = Event.json(event)
    end

    test "handles complex nested JSON" do
      event = %Event{data: ~s({"nested": {"array": [1, 2, 3]}, "bool": true})}

      assert {:ok, parsed} = Event.json(event)
      assert parsed["nested"]["array"] == [1, 2, 3]
      assert parsed["bool"] == true
    end
  end

  describe "json!/1" do
    test "parses JSON and returns result directly" do
      event = %Event{data: ~s({"key": "value"})}

      assert %{"key" => "value"} = Event.json!(event)
    end

    test "raises on invalid JSON" do
      event = %Event{data: "invalid"}

      assert_raise Jason.DecodeError, fn ->
        Event.json!(event)
      end
    end

    test "raises on nil data" do
      event = %Event{data: nil}

      assert_raise ArgumentError, fn ->
        Event.json!(event)
      end
    end

    test "raises on empty data" do
      event = %Event{data: ""}

      assert_raise ArgumentError, fn ->
        Event.json!(event)
      end
    end
  end

  describe "message?/1" do
    test "returns true for nil event type (default is message)" do
      event = %Event{data: "test"}
      assert Event.message?(event)
    end

    test "returns true for explicit message event type" do
      event = %Event{event: "message", data: "test"}
      assert Event.message?(event)
    end

    test "returns false for other event types" do
      event = %Event{event: "error", data: "test"}
      refute Event.message?(event)
    end
  end
end
