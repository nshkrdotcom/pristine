defmodule Tinkex.Types.TelemetryTypesTest do
  @moduledoc """
  Tests for telemetry type modules.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Types.Telemetry.{
    EventType,
    Severity,
    GenericEvent,
    SessionStartEvent,
    SessionEndEvent,
    UnhandledExceptionEvent,
    TelemetryEvent,
    TelemetryBatch,
    TelemetrySendRequest
  }

  # ========================================
  # EventType Tests
  # ========================================

  describe "EventType.parse/1" do
    test "parses SESSION_START" do
      assert EventType.parse("SESSION_START") == :session_start
    end

    test "parses SESSION_END" do
      assert EventType.parse("SESSION_END") == :session_end
    end

    test "parses UNHANDLED_EXCEPTION" do
      assert EventType.parse("UNHANDLED_EXCEPTION") == :unhandled_exception
    end

    test "parses GENERIC_EVENT" do
      assert EventType.parse("GENERIC_EVENT") == :generic_event
    end

    test "returns nil for unknown values" do
      assert EventType.parse("UNKNOWN") == nil
      assert EventType.parse(nil) == nil
    end
  end

  describe "EventType.to_string/1" do
    test "converts :session_start" do
      assert EventType.to_string(:session_start) == "SESSION_START"
    end

    test "converts :session_end" do
      assert EventType.to_string(:session_end) == "SESSION_END"
    end

    test "converts :unhandled_exception" do
      assert EventType.to_string(:unhandled_exception) == "UNHANDLED_EXCEPTION"
    end

    test "converts :generic_event" do
      assert EventType.to_string(:generic_event) == "GENERIC_EVENT"
    end
  end

  describe "EventType.values/0" do
    test "returns all event types" do
      values = EventType.values()
      assert :session_start in values
      assert :session_end in values
      assert :unhandled_exception in values
      assert :generic_event in values
      assert length(values) == 4
    end
  end

  # ========================================
  # Severity Tests
  # ========================================

  describe "Severity.parse/1" do
    test "parses DEBUG" do
      assert Severity.parse("DEBUG") == :debug
    end

    test "parses INFO" do
      assert Severity.parse("INFO") == :info
    end

    test "parses WARNING" do
      assert Severity.parse("WARNING") == :warning
    end

    test "parses ERROR" do
      assert Severity.parse("ERROR") == :error
    end

    test "parses CRITICAL" do
      assert Severity.parse("CRITICAL") == :critical
    end

    test "returns nil for unknown values" do
      assert Severity.parse("UNKNOWN") == nil
      assert Severity.parse(nil) == nil
    end
  end

  describe "Severity.to_string/1" do
    test "converts :debug" do
      assert Severity.to_string(:debug) == "DEBUG"
    end

    test "converts :info" do
      assert Severity.to_string(:info) == "INFO"
    end

    test "converts :warning" do
      assert Severity.to_string(:warning) == "WARNING"
    end

    test "converts :error" do
      assert Severity.to_string(:error) == "ERROR"
    end

    test "converts :critical" do
      assert Severity.to_string(:critical) == "CRITICAL"
    end
  end

  describe "Severity.values/0" do
    test "returns all severity levels" do
      values = Severity.values()
      assert :debug in values
      assert :info in values
      assert :warning in values
      assert :error in values
      assert :critical in values
      assert length(values) == 5
    end
  end

  # ========================================
  # GenericEvent Tests
  # ========================================

  describe "GenericEvent.new/1" do
    test "creates a GenericEvent with all fields" do
      now = DateTime.utc_now()

      event =
        GenericEvent.new(%{
          event: :generic_event,
          event_id: "evt-123",
          event_name: "test_event",
          event_session_index: 1,
          severity: :info,
          timestamp: now,
          event_data: %{"key" => "value"}
        })

      assert event.event == :generic_event
      assert event.event_id == "evt-123"
      assert event.event_name == "test_event"
      assert event.event_session_index == 1
      assert event.severity == :info
      assert event.timestamp == now
      assert event.event_data == %{"key" => "value"}
    end

    test "defaults event_data to empty map" do
      now = DateTime.utc_now()

      event =
        GenericEvent.new(%{
          event: :generic_event,
          event_id: "evt-123",
          event_name: "test_event",
          event_session_index: 1,
          severity: :info,
          timestamp: now
        })

      assert event.event_data == %{}
    end

    test "parses string field values" do
      now = DateTime.utc_now()

      event =
        GenericEvent.new(%{
          "event" => "GENERIC_EVENT",
          "event_id" => "evt-456",
          "event_name" => "parsed_event",
          "event_session_index" => 2,
          "severity" => "WARNING",
          "timestamp" => DateTime.to_iso8601(now),
          "event_data" => %{"foo" => "bar"}
        })

      assert event.event == :generic_event
      assert event.event_id == "evt-456"
      assert event.severity == :warning
    end
  end

  describe "GenericEvent JSON encoding" do
    test "encodes to JSON correctly" do
      now = DateTime.utc_now()

      event =
        GenericEvent.new(%{
          event: :generic_event,
          event_id: "evt-123",
          event_name: "test_event",
          event_session_index: 1,
          severity: :info,
          timestamp: now,
          event_data: %{"key" => "value"}
        })

      json = Jason.encode!(event)
      decoded = Jason.decode!(json)

      assert decoded["event"] == "GENERIC_EVENT"
      assert decoded["event_id"] == "evt-123"
      assert decoded["severity"] == "INFO"
      assert decoded["event_data"]["key"] == "value"
    end
  end

  # ========================================
  # SessionStartEvent Tests
  # ========================================

  describe "SessionStartEvent.new/1" do
    test "creates a SessionStartEvent" do
      now = DateTime.utc_now()

      event =
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "evt-start-1",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })

      assert event.event == :session_start
      assert event.event_id == "evt-start-1"
      assert event.event_session_index == 0
      assert event.severity == :info
      assert event.timestamp == now
    end

    test "parses string field values" do
      event =
        SessionStartEvent.new(%{
          "event" => "SESSION_START",
          "event_id" => "evt-start-2",
          "event_session_index" => 0,
          "severity" => "INFO",
          "timestamp" => "2025-01-06T12:00:00Z"
        })

      assert event.event == :session_start
      assert event.severity == :info
    end
  end

  describe "SessionStartEvent JSON encoding" do
    test "encodes to JSON correctly" do
      now = DateTime.utc_now()

      event =
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "evt-start-1",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })

      json = Jason.encode!(event)
      decoded = Jason.decode!(json)

      assert decoded["event"] == "SESSION_START"
      assert decoded["severity"] == "INFO"
    end
  end

  # ========================================
  # SessionEndEvent Tests
  # ========================================

  describe "SessionEndEvent.new/1" do
    test "creates a SessionEndEvent with duration" do
      now = DateTime.utc_now()

      event =
        SessionEndEvent.new(%{
          event: :session_end,
          event_id: "evt-end-1",
          event_session_index: 10,
          severity: :info,
          timestamp: now,
          duration: "PT1H30M"
        })

      assert event.event == :session_end
      assert event.event_id == "evt-end-1"
      assert event.duration == "PT1H30M"
    end

    test "parses string field values" do
      event =
        SessionEndEvent.new(%{
          "event" => "SESSION_END",
          "event_id" => "evt-end-2",
          "event_session_index" => 5,
          "severity" => "INFO",
          "timestamp" => "2025-01-06T12:00:00Z",
          "duration" => "PT30M"
        })

      assert event.event == :session_end
      assert event.duration == "PT30M"
    end
  end

  describe "SessionEndEvent JSON encoding" do
    test "encodes to JSON correctly" do
      now = DateTime.utc_now()

      event =
        SessionEndEvent.new(%{
          event: :session_end,
          event_id: "evt-end-1",
          event_session_index: 10,
          severity: :info,
          timestamp: now,
          duration: "PT1H30M"
        })

      json = Jason.encode!(event)
      decoded = Jason.decode!(json)

      assert decoded["event"] == "SESSION_END"
      assert decoded["duration"] == "PT1H30M"
    end
  end

  # ========================================
  # UnhandledExceptionEvent Tests
  # ========================================

  describe "UnhandledExceptionEvent.new/1" do
    test "creates an UnhandledExceptionEvent" do
      now = DateTime.utc_now()

      event =
        UnhandledExceptionEvent.new(%{
          event: :unhandled_exception,
          event_id: "evt-exc-1",
          event_session_index: 5,
          severity: :error,
          timestamp: now,
          error_message: "Something went wrong",
          error_type: "RuntimeError",
          traceback: "line 1\nline 2"
        })

      assert event.event == :unhandled_exception
      assert event.error_message == "Something went wrong"
      assert event.error_type == "RuntimeError"
      assert event.traceback == "line 1\nline 2"
    end

    test "traceback defaults to nil" do
      now = DateTime.utc_now()

      event =
        UnhandledExceptionEvent.new(%{
          event: :unhandled_exception,
          event_id: "evt-exc-2",
          event_session_index: 5,
          severity: :error,
          timestamp: now,
          error_message: "Error occurred",
          error_type: "ArgumentError"
        })

      assert event.traceback == nil
    end
  end

  describe "UnhandledExceptionEvent JSON encoding" do
    test "encodes to JSON correctly" do
      now = DateTime.utc_now()

      event =
        UnhandledExceptionEvent.new(%{
          event: :unhandled_exception,
          event_id: "evt-exc-1",
          event_session_index: 5,
          severity: :error,
          timestamp: now,
          error_message: "Something went wrong",
          error_type: "RuntimeError",
          traceback: "line 1\nline 2"
        })

      json = Jason.encode!(event)
      decoded = Jason.decode!(json)

      assert decoded["event"] == "UNHANDLED_EXCEPTION"
      assert decoded["error_message"] == "Something went wrong"
      assert decoded["error_type"] == "RuntimeError"
      assert decoded["traceback"] == "line 1\nline 2"
    end
  end

  # ========================================
  # TelemetryEvent Tests
  # ========================================

  describe "TelemetryEvent.parse/1" do
    test "parses GenericEvent" do
      now = DateTime.utc_now()

      data = %{
        "event" => "GENERIC_EVENT",
        "event_id" => "evt-123",
        "event_name" => "test",
        "event_session_index" => 1,
        "severity" => "INFO",
        "timestamp" => DateTime.to_iso8601(now),
        "event_data" => %{}
      }

      {:ok, event} = TelemetryEvent.parse(data)
      assert %GenericEvent{} = event
      assert event.event == :generic_event
    end

    test "parses SessionStartEvent" do
      data = %{
        "event" => "SESSION_START",
        "event_id" => "evt-start",
        "event_session_index" => 0,
        "severity" => "INFO",
        "timestamp" => "2025-01-06T12:00:00Z"
      }

      {:ok, event} = TelemetryEvent.parse(data)
      assert %SessionStartEvent{} = event
      assert event.event == :session_start
    end

    test "parses SessionEndEvent" do
      data = %{
        "event" => "SESSION_END",
        "event_id" => "evt-end",
        "event_session_index" => 10,
        "severity" => "INFO",
        "timestamp" => "2025-01-06T12:00:00Z",
        "duration" => "PT1H"
      }

      {:ok, event} = TelemetryEvent.parse(data)
      assert %SessionEndEvent{} = event
      assert event.duration == "PT1H"
    end

    test "parses UnhandledExceptionEvent" do
      data = %{
        "event" => "UNHANDLED_EXCEPTION",
        "event_id" => "evt-exc",
        "event_session_index" => 5,
        "severity" => "ERROR",
        "timestamp" => "2025-01-06T12:00:00Z",
        "error_message" => "Oops",
        "error_type" => "RuntimeError"
      }

      {:ok, event} = TelemetryEvent.parse(data)
      assert %UnhandledExceptionEvent{} = event
      assert event.error_message == "Oops"
    end

    test "returns error for unknown event type" do
      data = %{"event" => "UNKNOWN"}
      assert {:error, :unknown_event_type} = TelemetryEvent.parse(data)
    end
  end

  describe "TelemetryEvent.type_of/1" do
    test "identifies event struct types" do
      now = DateTime.utc_now()

      generic =
        GenericEvent.new(%{
          event: :generic_event,
          event_id: "1",
          event_name: "test",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })

      start_event =
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "2",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })

      assert TelemetryEvent.type_of(generic) == :generic_event
      assert TelemetryEvent.type_of(start_event) == :session_start
    end
  end

  # ========================================
  # TelemetryBatch Tests
  # ========================================

  describe "TelemetryBatch.new/1" do
    test "creates a TelemetryBatch" do
      now = DateTime.utc_now()

      event =
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "evt-1",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })

      batch =
        TelemetryBatch.new(%{
          events: [event],
          platform: "elixir",
          sdk_version: "0.1.0",
          session_id: "sess-123"
        })

      assert batch.platform == "elixir"
      assert batch.sdk_version == "0.1.0"
      assert batch.session_id == "sess-123"
      assert length(batch.events) == 1
    end

    test "accepts string keys" do
      batch =
        TelemetryBatch.new(%{
          "events" => [],
          "platform" => "python",
          "sdk_version" => "1.0.0",
          "session_id" => "sess-456"
        })

      assert batch.platform == "python"
    end
  end

  describe "TelemetryBatch JSON encoding" do
    test "encodes batch correctly" do
      now = DateTime.utc_now()

      event =
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "evt-1",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })

      batch =
        TelemetryBatch.new(%{
          events: [event],
          platform: "elixir",
          sdk_version: "0.1.0",
          session_id: "sess-123"
        })

      json = Jason.encode!(batch)
      decoded = Jason.decode!(json)

      assert decoded["platform"] == "elixir"
      assert decoded["sdk_version"] == "0.1.0"
      assert length(decoded["events"]) == 1
    end
  end

  # ========================================
  # TelemetrySendRequest Tests
  # ========================================

  describe "TelemetrySendRequest.new/1" do
    test "creates a TelemetrySendRequest" do
      now = DateTime.utc_now()

      event =
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "evt-1",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })

      request =
        TelemetrySendRequest.new(%{
          events: [event],
          platform: "elixir",
          sdk_version: "0.1.0",
          session_id: "sess-123"
        })

      assert request.platform == "elixir"
      assert request.sdk_version == "0.1.0"
      assert request.session_id == "sess-123"
      assert length(request.events) == 1
    end
  end

  describe "TelemetrySendRequest JSON encoding" do
    test "encodes request correctly" do
      now = DateTime.utc_now()

      event =
        GenericEvent.new(%{
          event: :generic_event,
          event_id: "evt-1",
          event_name: "test",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })

      request =
        TelemetrySendRequest.new(%{
          events: [event],
          platform: "elixir",
          sdk_version: "0.1.0",
          session_id: "sess-123"
        })

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["platform"] == "elixir"
      assert decoded["events"] |> hd() |> Map.get("event") == "GENERIC_EVENT"
    end
  end
end
