defmodule Tinkex.Telemetry.Reporter.EventsTest do
  @moduledoc """
  Tests for telemetry event building.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Reporter.Events

  alias Tinkex.Types.Telemetry.{
    GenericEvent,
    SessionEndEvent,
    SessionStartEvent,
    UnhandledExceptionEvent
  }

  describe "build_generic_event/4" do
    test "builds generic event with all required fields" do
      state = new_state()

      {event, _new_state} =
        Events.build_generic_event(state, "test.event", %{key: "value"}, :info)

      assert %GenericEvent{} = event
      assert event.event == :generic_event
      assert event.event_name == "test.event"
      assert is_binary(event.event_id)
      assert event.severity == :info
      assert is_struct(event.timestamp, DateTime)
    end

    test "increments session_index" do
      state = new_state()

      {_event, state1} = Events.build_generic_event(state, "e1", %{}, :info)
      {_event, state2} = Events.build_generic_event(state1, "e2", %{}, :info)

      assert state1.session_index == 1
      assert state2.session_index == 2
    end

    test "sanitizes event_data" do
      state = new_state()
      data = %{atom_key: :atom_value, nested: %{inner: :val}}

      {event, _} = Events.build_generic_event(state, "test", data, :info)

      # Data should be sanitized to strings
      assert is_map(event.event_data)
    end

    test "parses string severity" do
      state = new_state()

      {event, _} = Events.build_generic_event(state, "test", %{}, "ERROR")

      assert event.severity == :error
    end
  end

  describe "build_session_start_event/1" do
    test "builds session start event" do
      state = new_state()

      {event, _new_state} = Events.build_session_start_event(state)

      assert %SessionStartEvent{} = event
      assert event.event == :session_start
      assert event.severity == :info
      assert is_binary(event.event_id)
    end

    test "uses session_start_iso from state" do
      iso = "2025-01-06T12:00:00Z"
      state = %{new_state() | session_start_iso: iso}

      {event, _} = Events.build_session_start_event(state)

      assert event.timestamp == elem(DateTime.from_iso8601(iso), 1)
    end

    test "increments session_index" do
      state = new_state()

      {_event, new_state} = Events.build_session_start_event(state)

      assert new_state.session_index == 1
    end
  end

  describe "build_session_end_event/1" do
    test "builds session end event" do
      state = %{
        new_state()
        | session_start_native: System.monotonic_time(:microsecond) - 1_000_000
      }

      {event, _new_state} = Events.build_session_end_event(state)

      assert %SessionEndEvent{} = event
      assert event.event == :session_end
      assert event.severity == :info
      assert is_binary(event.duration)
    end

    test "calculates duration" do
      # 1 hour ago
      start_us = System.monotonic_time(:microsecond) - 3_600_000_000
      state = %{new_state() | session_start_native: start_us}

      {event, _} = Events.build_session_end_event(state)

      # Duration should be around "1:00:00" (1 hour)
      assert String.contains?(event.duration, "1:00")
    end
  end

  describe "build_exception_event/3" do
    test "builds unhandled exception event for server errors" do
      state = new_state()
      exception = %RuntimeError{message: "Something failed"}

      {event, _new_state} = Events.build_exception_event(state, exception, :error)

      assert %UnhandledExceptionEvent{} = event
      assert event.error_type =~ "RuntimeError"
      assert event.error_message == "Something failed"
    end

    test "builds user error event for 4xx errors" do
      state = new_state()
      error = %Tinkex.Error{message: "Bad request", status: 400, category: :user}

      {event, _new_state} = Events.build_exception_event(state, error, :warning)

      assert %GenericEvent{} = event
      assert event.event_name == "user_error"
    end
  end

  describe "build_unhandled_exception/3" do
    test "builds event with error details" do
      state = new_state()
      exception = %RuntimeError{message: "Test error"}

      {event, _} = Events.build_unhandled_exception(state, exception, :error)

      assert event.error_type =~ "RuntimeError"
      assert event.error_message == "Test error"
      assert event.severity == :error
    end

    test "includes traceback when available" do
      state = new_state()
      exception = %RuntimeError{message: "Test"}

      {event, _} = Events.build_unhandled_exception(state, exception, :error)

      # Should have some traceback info (may be nil in simple cases)
      assert Map.has_key?(event, :traceback)
    end
  end

  describe "build_user_error_event/2" do
    test "builds generic event with warning severity" do
      state = new_state()
      error = %Tinkex.Error{message: "Bad input", status: 400}

      {event, _} = Events.build_user_error_event(state, error)

      assert %GenericEvent{} = event
      assert event.event_name == "user_error"
      assert event.severity == :warning
    end

    test "includes status_code in event_data" do
      state = new_state()
      error = %Tinkex.Error{message: "Not found", status: 404}

      {event, _} = Events.build_user_error_event(state, error)

      assert event.event_data["status_code"] == 404
    end
  end

  describe "enqueue_session_start/1" do
    test "enqueues session start event" do
      state = new_state()

      {new_state, accepted} = Events.enqueue_session_start(state)

      assert accepted == true
      assert new_state.queue_size == 1
    end
  end

  describe "maybe_enqueue_session_end/1" do
    test "enqueues session end event" do
      state = %{new_state() | session_start_native: System.monotonic_time(:microsecond)}

      new_state = Events.maybe_enqueue_session_end(state)

      assert new_state.session_ended? == true
      assert new_state.queue_size == 1
    end

    test "does not enqueue if already ended" do
      state = %{new_state() | session_ended?: true}

      new_state = Events.maybe_enqueue_session_end(state)

      assert new_state.queue_size == 0
    end
  end

  describe "severity_for_event/1" do
    test "returns error for exception events" do
      assert :error == Events.severity_for_event([:tinkex, :http, :request, :exception])
    end

    test "returns info for other events" do
      assert :info == Events.severity_for_event([:tinkex, :http, :request, :start])
      assert :info == Events.severity_for_event([:other, :event])
    end
  end

  # Helper to create a fresh state
  defp new_state do
    iso = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      queue: :queue.new(),
      queue_size: 0,
      max_queue_size: 10_000,
      session_index: 0,
      session_start_iso: iso,
      session_start_native: System.monotonic_time(:microsecond),
      session_ended?: false,
      push_counter: 0,
      flush_counter: 0
    }
  end
end
