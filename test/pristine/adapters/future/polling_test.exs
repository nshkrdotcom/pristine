defmodule Pristine.Adapters.Future.PollingTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  import Mox

  alias Pristine.Adapters.Future.Polling
  alias Pristine.Core.{Context, Request, Response}

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "poll/3" do
    test "returns task that polls until complete" do
      poll_count = :counters.new(1, [:atomics])

      expect(Pristine.SerializerMock, :encode, 3, fn _payload, _opts ->
        {:ok, ~s({"request_id":"req_123"})}
      end)

      expect(Pristine.TransportMock, :send, 3, fn _request, _context ->
        count = :counters.get(poll_count, 1)
        :counters.add(poll_count, 1, 1)

        response =
          if count < 2 do
            %{"type" => "try_again", "status" => "pending"}
          else
            %{"type" => "completed", "result" => %{"value" => 42}}
          end

        {:ok, %Response{status: 200, body: Jason.encode!(response)}}
      end)

      expect(Pristine.SerializerMock, :decode, 3, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      context = build_context()
      opts = [poll_interval_ms: 10, max_poll_time_ms: 5000, sleep_fun: fn _ -> :ok end]

      {:ok, task} = Polling.poll("req_123", context, opts)

      assert {:ok, result} = Polling.await(task, 10_000)
      assert result["type"] == "completed"
      assert result["result"]["value"] == 42
    end

    test "times out after max_poll_time_ms" do
      # Use stub instead of expect for unlimited calls
      stub(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"request_id":"req_123"})}
      end)

      stub(Pristine.TransportMock, :send, fn _request, _context ->
        response = %{"type" => "try_again", "status" => "pending"}
        {:ok, %Response{status: 200, body: Jason.encode!(response)}}
      end)

      stub(Pristine.SerializerMock, :decode, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      context = build_context()
      # Very short timeout
      opts = [poll_interval_ms: 10, max_poll_time_ms: 1, sleep_fun: fn _ -> :ok end]

      {:ok, task} = Polling.poll("req_123", context, opts)

      assert {:error, :poll_timeout} = Polling.await(task, 5_000)
    end

    test "handles completed status response" do
      expect(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"request_id":"req_123"})}
      end)

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        response = %{"status" => "complete", "result" => "done"}
        {:ok, %Response{status: 200, body: Jason.encode!(response)}}
      end)

      expect(Pristine.SerializerMock, :decode, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      context = build_context()
      opts = [poll_interval_ms: 10, sleep_fun: fn _ -> :ok end]

      {:ok, task} = Polling.poll("req_123", context, opts)

      assert {:ok, %{"status" => "complete"}} = Polling.await(task, 5_000)
    end

    test "handles failed response" do
      expect(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"request_id":"req_123"})}
      end)

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        response = %{"type" => "failed", "error" => "Something went wrong"}
        {:ok, %Response{status: 200, body: Jason.encode!(response)}}
      end)

      expect(Pristine.SerializerMock, :decode, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      context = build_context()
      opts = [poll_interval_ms: 10, sleep_fun: fn _ -> :ok end]

      {:ok, task} = Polling.poll("req_123", context, opts)

      assert {:error, {:request_failed, "Something went wrong"}} = Polling.await(task, 5_000)
    end

    test "retries on retriable HTTP errors" do
      call_count = :counters.new(1, [:atomics])

      expect(Pristine.SerializerMock, :encode, 2, fn _payload, _opts ->
        {:ok, ~s({"request_id":"req_123"})}
      end)

      expect(Pristine.TransportMock, :send, 2, fn _request, _context ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count < 1 do
          {:ok, %Response{status: 503, body: "Service Unavailable"}}
        else
          response = %{"type" => "completed", "result" => "done"}
          {:ok, %Response{status: 200, body: Jason.encode!(response)}}
        end
      end)

      expect(Pristine.SerializerMock, :decode, 2, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      context = build_context()
      opts = [poll_interval_ms: 10, max_poll_time_ms: 5000, sleep_fun: fn _ -> :ok end]

      {:ok, task} = Polling.poll("req_123", context, opts)

      assert {:ok, %{"type" => "completed"}} = Polling.await(task, 10_000)
    end

    test "calls on_state_change callback" do
      test_pid = self()

      # Use stub for unlimited calls since we're testing timeout behavior
      stub(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"request_id":"req_123"})}
      end)

      stub(Pristine.TransportMock, :send, fn _request, _context ->
        {:ok,
         %Response{
           status: 200,
           body: Jason.encode!(%{"type" => "try_again", "queue_state" => "active"})
         }}
      end)

      stub(Pristine.SerializerMock, :decode, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      context = build_context()

      opts = [
        poll_interval_ms: 10,
        max_poll_time_ms: 30,
        # Use explicit constant backoff to avoid math issues
        backoff: :none,
        sleep_fun: fn _ -> :ok end,
        on_state_change: fn response ->
          send(test_pid, {:state_change, response})
          :ok
        end
      ]

      {:ok, task} = Polling.poll("req_123", context, opts)

      # Will timeout, but should have called on_state_change
      Polling.await(task, 1_000)

      assert_received {:state_change, %{"type" => "try_again"}}
    end

    test "caches results for subsequent polls" do
      request_id = "req_cache"

      expect(Pristine.SerializerMock, :encode, fn _payload, _opts ->
        {:ok, ~s({"request_id":"#{request_id}"})}
      end)

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        response = %{"type" => "completed", "result" => %{"value" => 7}}
        {:ok, %Response{status: 200, body: Jason.encode!(response)}}
      end)

      expect(Pristine.SerializerMock, :decode, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      context = build_context()
      opts = [poll_interval_ms: 10, sleep_fun: fn _ -> :ok end]

      {:ok, task1} = Polling.poll(request_id, context, opts)
      assert {:ok, %{"type" => "completed"} = result} = Polling.await(task1, 5_000)

      {:ok, task2} = Polling.poll(request_id, context, opts)
      assert {:ok, ^result} = Polling.await(task2, 5_000)
    end

    test "handles queue state on 408 responses" do
      test_pid = self()
      request_id = "req_queue"
      call_count = :counters.new(1, [:atomics])

      expect(Pristine.SerializerMock, :encode, 2, fn _payload, _opts ->
        {:ok, ~s({"request_id":"#{request_id}"})}
      end)

      expect(Pristine.TransportMock, :send, 2, fn _request, _context ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count < 1 do
          {:ok,
           %Response{
             status: 408,
             body: Jason.encode!(%{"queue_state" => "paused_rate_limit"})
           }}
        else
          response = %{"type" => "completed", "result" => "done"}
          {:ok, %Response{status: 200, body: Jason.encode!(response)}}
        end
      end)

      expect(Pristine.SerializerMock, :decode, 2, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      context = build_context()

      opts = [
        poll_interval_ms: 10,
        backoff: :none,
        sleep_fun: fn _ -> :ok end,
        on_state_change: fn payload ->
          send(test_pid, {:queue_state, payload.queue_state})
          :ok
        end
      ]

      {:ok, task} = Polling.poll(request_id, context, opts)

      assert {:ok, %{"type" => "completed"}} = Polling.await(task, 5_000)
      assert_received {:queue_state, :paused_rate_limit}
    end

    test "adds telemetry headers on each poll attempt" do
      request_id = "req_headers"
      call_count = :counters.new(1, [:atomics])

      expect(Pristine.SerializerMock, :encode, 2, fn _payload, _opts ->
        {:ok, ~s({"request_id":"#{request_id}"})}
      end)

      expect(Pristine.TransportMock, :send, 2, fn %Request{headers: headers}, _context ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        assert headers["x-stainless-retry-count"] == to_string(count)
        assert headers["X-Stainless-OS"]

        response =
          if count < 1 do
            %{"type" => "try_again"}
          else
            %{"type" => "completed", "result" => "done"}
          end

        {:ok, %Response{status: 200, body: Jason.encode!(response)}}
      end)

      expect(Pristine.SerializerMock, :decode, 2, fn body, _schema, _opts ->
        Jason.decode(body)
      end)

      context = build_context()
      opts = [poll_interval_ms: 10, backoff: :none, sleep_fun: fn _ -> :ok end]

      {:ok, task} = Polling.poll(request_id, context, opts)
      assert {:ok, %{"type" => "completed"}} = Polling.await(task, 5_000)
    end
  end

  describe "await/2" do
    test "returns result when task completes" do
      task = Task.async(fn -> {:ok, %{"status" => "done"}} end)
      assert {:ok, %{"status" => "done"}} = Polling.await(task, 5_000)
    end

    test "returns error when task times out" do
      task = Task.async(fn -> Process.sleep(:infinity) end)
      assert {:error, :await_timeout} = Polling.await(task, 10)
    end

    test "returns error when task raises" do
      # Trap exits so we don't get killed when the task exits
      Process.flag(:trap_exit, true)

      {result, _log} =
        with_log(fn ->
          task = Task.async(fn -> raise "boom" end)
          Polling.await(task, 1_000)
        end)

      assert {:error, {:task_exit, _}} = result

      # Clean up the exit message
      receive do
        {:EXIT, _, _} -> :ok
      after
        100 -> :ok
      end
    end
  end

  describe "combine/3" do
    test "combines futures and applies transform" do
      task1 = Task.async(fn -> {:ok, 1} end)
      task2 = Task.async(fn -> {:ok, 2} end)

      {:ok, combined} = Polling.combine([task1, task2], fn results -> Enum.sum(results) end)

      assert {:ok, 3} = Polling.await(combined, 1_000)
    end

    test "returns error when a future fails" do
      task1 = Task.async(fn -> {:ok, 1} end)
      task2 = Task.async(fn -> {:error, :boom} end)

      {:ok, combined} = Polling.combine([task1, task2], fn results -> Enum.sum(results) end)

      assert {:error, :boom} = Polling.await(combined, 1_000)
    end
  end

  defp build_context do
    %Context{
      base_url: "http://localhost:4000",
      headers: %{},
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock
    }
  end
end
