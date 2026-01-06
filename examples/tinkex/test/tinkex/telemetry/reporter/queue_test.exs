defmodule Tinkex.Telemetry.Reporter.QueueTest do
  @moduledoc """
  Tests for telemetry queue operations.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Reporter.Queue

  describe "enqueue_event/2" do
    test "adds event to empty queue" do
      state = new_state()
      event = %{event: "test"}

      {new_state, accepted} = Queue.enqueue_event(state, event)

      assert accepted == true
      assert new_state.queue_size == 1
      assert new_state.push_counter == 1
      assert :queue.len(new_state.queue) == 1
    end

    test "adds multiple events to queue" do
      state = new_state()

      {state, _} = Queue.enqueue_event(state, %{event: "e1"})
      {state, _} = Queue.enqueue_event(state, %{event: "e2"})
      {state, _} = Queue.enqueue_event(state, %{event: "e3"})

      assert state.queue_size == 3
      assert state.push_counter == 3
    end

    test "rejects event when queue is full" do
      state = %{new_state() | max_queue_size: 2}

      {state, true} = Queue.enqueue_event(state, %{event: "e1"})
      {state, true} = Queue.enqueue_event(state, %{event: "e2"})
      {state, rejected} = Queue.enqueue_event(state, %{event: "e3"})

      assert rejected == false
      assert state.queue_size == 2
      assert state.push_counter == 2
    end

    test "increments push_counter on each enqueue" do
      state = new_state()

      {state1, _} = Queue.enqueue_event(state, %{event: "e1"})
      {state2, _} = Queue.enqueue_event(state1, %{event: "e2"})

      assert state1.push_counter == 1
      assert state2.push_counter == 2
    end
  end

  describe "drain_queue/1" do
    test "returns empty list for empty queue" do
      state = new_state()

      {events, new_state} = Queue.drain_queue(state)

      assert events == []
      assert new_state.queue_size == 0
    end

    test "returns all events and empties queue" do
      state = new_state()
      {state, _} = Queue.enqueue_event(state, %{event: "e1"})
      {state, _} = Queue.enqueue_event(state, %{event: "e2"})
      {state, _} = Queue.enqueue_event(state, %{event: "e3"})

      {events, new_state} = Queue.drain_queue(state)

      assert length(events) == 3
      assert new_state.queue_size == 0
      assert :queue.is_empty(new_state.queue)
    end

    test "preserves FIFO order" do
      state = new_state()
      {state, _} = Queue.enqueue_event(state, %{event: "first"})
      {state, _} = Queue.enqueue_event(state, %{event: "second"})
      {state, _} = Queue.enqueue_event(state, %{event: "third"})

      {events, _new_state} = Queue.drain_queue(state)

      assert Enum.map(events, & &1.event) == ["first", "second", "third"]
    end

    test "increments flush_counter by events count" do
      state = new_state()
      {state, _} = Queue.enqueue_event(state, %{event: "e1"})
      {state, _} = Queue.enqueue_event(state, %{event: "e2"})

      {_events, new_state} = Queue.drain_queue(state)

      assert new_state.flush_counter == 2
    end

    test "accumulates flush_counter across multiple drains" do
      state = new_state()
      {state, _} = Queue.enqueue_event(state, %{event: "e1"})
      {_events, state} = Queue.drain_queue(state)

      {state, _} = Queue.enqueue_event(state, %{event: "e2"})
      {state, _} = Queue.enqueue_event(state, %{event: "e3"})
      {_events, state} = Queue.drain_queue(state)

      assert state.flush_counter == 3
    end
  end

  describe "maybe_request_flush/1" do
    test "sends :flush message when queue reaches threshold" do
      state = %{new_state() | flush_threshold: 2, queue_size: 2}

      _new_state = Queue.maybe_request_flush(state)

      assert_received :flush
    end

    test "does not send :flush message when below threshold" do
      state = %{new_state() | flush_threshold: 10, queue_size: 5}

      _new_state = Queue.maybe_request_flush(state)

      refute_received :flush
    end

    test "returns state unchanged" do
      state = %{new_state() | flush_threshold: 2, queue_size: 1}

      new_state = Queue.maybe_request_flush(state)

      assert new_state == state
    end
  end

  describe "maybe_schedule_flush/1" do
    test "schedules flush when interval is positive" do
      state = %{new_state() | flush_interval_ms: 100}

      new_state = Queue.maybe_schedule_flush(state)

      assert is_reference(new_state.flush_timer)
      # Clean up timer
      Process.cancel_timer(new_state.flush_timer)
    end

    test "does not schedule when interval is 0" do
      state = %{new_state() | flush_interval_ms: 0}

      new_state = Queue.maybe_schedule_flush(state)

      assert new_state == state
    end

    test "does not schedule when interval is nil" do
      state = %{new_state() | flush_interval_ms: nil}

      new_state = Queue.maybe_schedule_flush(state)

      assert new_state == state
    end
  end

  describe "wait_until_drained/2" do
    test "returns true when already drained" do
      state = %{new_state() | push_counter: 5, flush_counter: 5}

      result = Queue.wait_until_drained(state, 100)

      assert result == true
    end

    test "returns true when flush_counter exceeds push_counter" do
      state = %{new_state() | push_counter: 5, flush_counter: 10}

      result = Queue.wait_until_drained(state, 100)

      assert result == true
    end

    test "returns false when not drained within timeout" do
      state = %{new_state() | push_counter: 10, flush_counter: 0}

      result = Queue.wait_until_drained(state, 50)

      assert result == false
    end
  end

  # Helper to create a fresh state
  defp new_state do
    %{
      queue: :queue.new(),
      queue_size: 0,
      max_queue_size: 10_000,
      flush_threshold: 100,
      flush_interval_ms: 10_000,
      flush_timer: nil,
      push_counter: 0,
      flush_counter: 0
    }
  end
end
