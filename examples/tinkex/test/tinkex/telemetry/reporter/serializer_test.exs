defmodule Tinkex.Telemetry.Reporter.SerializerTest do
  @moduledoc """
  Tests for telemetry event serialization and sanitization.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Reporter.Serializer

  alias Tinkex.Types.Telemetry.{
    GenericEvent,
    SessionEndEvent,
    SessionStartEvent,
    UnhandledExceptionEvent
  }

  describe "sanitize/1" do
    test "passes through strings unchanged" do
      assert "hello" == Serializer.sanitize("hello")
    end

    test "passes through integers unchanged" do
      assert 42 == Serializer.sanitize(42)
    end

    test "passes through floats unchanged" do
      assert 3.14 == Serializer.sanitize(3.14)
    end

    test "passes through booleans unchanged" do
      assert true == Serializer.sanitize(true)
      assert false == Serializer.sanitize(false)
    end

    test "passes through nil unchanged" do
      assert nil == Serializer.sanitize(nil)
    end

    test "converts atoms to strings" do
      assert "hello" == Serializer.sanitize(:hello)
      assert "info" == Serializer.sanitize(:info)
    end

    test "converts struct to sanitized map" do
      struct = %GenericEvent{
        event: :generic_event,
        event_id: "abc123",
        event_session_index: 1,
        severity: :info,
        timestamp: ~U[2025-01-06T00:00:00Z],
        event_name: "test",
        event_data: %{}
      }

      result = Serializer.sanitize(struct)
      assert is_map(result)
      refute Map.has_key?(result, :__struct__)
      assert result["severity"] == "info"
    end

    test "recursively sanitizes map values" do
      map = %{
        key: :value,
        nested: %{inner: :atom}
      }

      result = Serializer.sanitize(map)
      assert result["key"] == "value"
      assert result["nested"]["inner"] == "atom"
    end

    test "converts map keys to strings" do
      map = %{"string_key" => 2, atom_key: 1}
      result = Serializer.sanitize(map)
      assert Map.has_key?(result, "atom_key")
      assert Map.has_key?(result, "string_key")
    end

    test "recursively sanitizes lists" do
      list = [:a, :b, %{nested: :value}]
      result = Serializer.sanitize(list)
      assert result == ["a", "b", %{"nested" => "value"}]
    end

    test "inspects unknown types" do
      pid = self()
      result = Serializer.sanitize(pid)
      assert is_binary(result)
      assert String.contains?(result, "#PID")
    end

    test "handles tuples by inspecting" do
      tuple = {:ok, "value"}
      result = Serializer.sanitize(tuple)
      assert is_binary(result)
      assert String.contains?(result, "ok")
    end
  end

  describe "event_to_map/1" do
    test "converts GenericEvent to map" do
      event = %GenericEvent{
        event: :generic_event,
        event_id: "abc123",
        event_session_index: 1,
        severity: :info,
        timestamp: ~U[2025-01-06T00:00:00Z],
        event_name: "test.event",
        event_data: %{key: "value"}
      }

      result = Serializer.event_to_map(event)
      assert is_map(result)
      assert result.event_id == "abc123"
    end

    test "converts SessionStartEvent to map" do
      event = %SessionStartEvent{
        event: :session_start,
        event_id: "start123",
        event_session_index: 0,
        severity: :info,
        timestamp: ~U[2025-01-06T00:00:00Z]
      }

      result = Serializer.event_to_map(event)
      assert is_map(result)
      assert result.event_id == "start123"
    end

    test "converts SessionEndEvent to map" do
      event = %SessionEndEvent{
        event: :session_end,
        event_id: "end123",
        event_session_index: 10,
        severity: :info,
        timestamp: ~U[2025-01-06T01:00:00Z],
        duration: "1:00:00"
      }

      result = Serializer.event_to_map(event)
      assert is_map(result)
      assert result.event_id == "end123"
      assert result.duration == "1:00:00"
    end

    test "converts UnhandledExceptionEvent to map" do
      event = %UnhandledExceptionEvent{
        event: :unhandled_exception,
        event_id: "exc123",
        event_session_index: 5,
        severity: :error,
        timestamp: ~U[2025-01-06T00:30:00Z],
        error_type: "RuntimeError",
        error_message: "Something went wrong",
        traceback: "..."
      }

      result = Serializer.event_to_map(event)
      assert is_map(result)
      assert result.error_type == "RuntimeError"
    end

    test "returns plain maps unchanged" do
      map = %{key: "value", event: "custom"}
      assert map == Serializer.event_to_map(map)
    end
  end

  describe "build_request/2" do
    test "builds request with session_id and platform" do
      events = []

      state = %{
        session_id: "session-123"
      }

      result = Serializer.build_request(events, state)
      assert result.session_id == "session-123"
      assert is_binary(result.platform)
      assert is_binary(result.sdk_version)
      assert result.events == []
    end

    test "includes serialized events" do
      events = [
        %GenericEvent{
          event: :generic_event,
          event_id: "ev1",
          event_session_index: 0,
          severity: :info,
          timestamp: ~U[2025-01-06T00:00:00Z],
          event_name: "test",
          event_data: %{}
        }
      ]

      state = %{session_id: "session-123"}
      result = Serializer.build_request(events, state)
      assert length(result.events) == 1
    end

    test "converts struct events to maps" do
      events = [
        %SessionStartEvent{
          event: :session_start,
          event_id: "start1",
          event_session_index: 0,
          severity: :info,
          timestamp: ~U[2025-01-06T00:00:00Z]
        }
      ]

      state = %{session_id: "session-123"}
      result = Serializer.build_request(events, state)
      [event_map] = result.events
      assert is_map(event_map)
    end
  end

  describe "platform/0" do
    test "returns os type as string" do
      platform = Serializer.platform()
      assert is_binary(platform)
      # Should be in format "type/flavor" e.g. "unix/linux"
      assert String.contains?(platform, "/")
    end

    test "contains unix or win32 in result" do
      platform = Serializer.platform()
      # Common platforms
      assert String.contains?(platform, "unix") or String.contains?(platform, "win32")
    end
  end
end
