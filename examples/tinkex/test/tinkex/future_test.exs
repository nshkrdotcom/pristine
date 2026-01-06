defmodule Tinkex.FutureTest do
  use ExUnit.Case, async: false

  alias Tinkex.Future
  alias Tinkex.Error

  defmodule MockClient do
    @behaviour Tinkex.HTTPClient

    @impl true
    def post("/api/v1/retrieve_future", %{request_id: request_id}, opts) do
      test_pid = opts[:test_pid] || self()
      send(test_pid, {:mock_post, request_id, opts})

      case :ets.lookup(:mock_responses, :responses) do
        [{:responses, [response | rest]}] ->
          :ets.insert(:mock_responses, {:responses, rest})
          response

        [{:responses, response}] when not is_list(response) ->
          response

        _ ->
          {:ok, %{"status" => "completed", "result" => %{"data" => "success"}}}
      end
    end

    @impl true
    def get(_path, _opts), do: {:error, Error.new(:api_status, "Method not allowed", status: 405)}

    @impl true
    def delete(_path, _opts),
      do: {:error, Error.new(:api_status, "Method not allowed", status: 405)}
  end

  setup do
    # Create ETS table for cross-process mock responses
    if :ets.whereis(:mock_responses) == :undefined do
      :ets.new(:mock_responses, [:named_table, :public, :set])
    end

    :ets.delete_all_objects(:mock_responses)

    config = %Tinkex.Config{
      base_url: "https://example.com",
      api_key: "tml-test-key",
      timeout: 60_000,
      max_retries: 3,
      http_client: MockClient
    }

    {:ok, config: config}
  end

  defp set_mock_responses(responses) do
    :ets.insert(:mock_responses, {:responses, responses})
  end

  describe "poll/2" do
    test "accepts request_id string", %{config: config} do
      task = Future.poll("test-request-123", config: config, sleep_fun: fn _ -> :ok end)
      assert %Task{} = task
      {:ok, result} = Task.await(task)
      assert result["data"] == "success"
    end

    test "accepts map with :request_id", %{config: config} do
      task =
        Future.poll(%{request_id: "test-request-123"}, config: config, sleep_fun: fn _ -> :ok end)

      {:ok, result} = Task.await(task)
      assert result["data"] == "success"
    end

    test "accepts map with string request_id key", %{config: config} do
      task =
        Future.poll(%{"request_id" => "test-request-123"},
          config: config,
          sleep_fun: fn _ -> :ok end
        )

      {:ok, result} = Task.await(task)
      assert result["data"] == "success"
    end

    test "raises on invalid request_id", %{config: config} do
      assert_raise ArgumentError, ~r/expected request id string or map/, fn ->
        Future.poll(123, config: config)
      end
    end
  end

  describe "await/2" do
    test "returns result on success", %{config: config} do
      task = Future.poll("test-request", config: config, sleep_fun: fn _ -> :ok end)
      assert {:ok, %{"data" => "success"}} = Future.await(task)
    end
  end

  describe "await_many/2" do
    test "awaits multiple tasks", %{config: config} do
      tasks = [
        Future.poll("request-1", config: config, sleep_fun: fn _ -> :ok end),
        Future.poll("request-2", config: config, sleep_fun: fn _ -> :ok end),
        Future.poll("request-3", config: config, sleep_fun: fn _ -> :ok end)
      ]

      results = Future.await_many(tasks)

      assert length(results) == 3

      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end
  end

  describe "completed response handling" do
    test "returns result immediately on completed status", %{config: config} do
      set_mock_responses({:ok, %{"status" => "completed", "result" => %{"value" => 42}}})

      task = Future.poll("test-request", config: config, sleep_fun: fn _ -> :ok end)
      assert {:ok, %{"value" => 42}} = Future.await(task)
    end
  end

  describe "pending response handling" do
    test "continues polling on pending status", %{config: config} do
      set_mock_responses([
        {:ok, %{"status" => "pending"}},
        {:ok, %{"status" => "pending"}},
        {:ok, %{"status" => "completed", "result" => %{"done" => true}}}
      ])

      sleep_count = :counters.new(1, [:atomics])

      task =
        Future.poll("test-request",
          config: config,
          sleep_fun: fn _ms ->
            :counters.add(sleep_count, 1, 1)
          end
        )

      {:ok, result} = Future.await(task)
      assert result["done"] == true
      # Should have slept twice (after first two pending responses)
      assert :counters.get(sleep_count, 1) == 2
    end
  end

  describe "failed response handling" do
    test "returns error on user category failure", %{config: config} do
      set_mock_responses(
        {:ok,
         %{
           "status" => "failed",
           "error" => %{"message" => "Invalid input", "category" => "user"}
         }}
      )

      task = Future.poll("test-request", config: config, sleep_fun: fn _ -> :ok end)
      assert {:error, %Error{type: :request_failed, category: :user}} = Future.await(task)
    end

    test "retries on server category failure", %{config: config} do
      set_mock_responses([
        {:ok,
         %{
           "status" => "failed",
           "error" => %{"message" => "Server error", "category" => "server"}
         }},
        {:ok, %{"status" => "completed", "result" => %{"recovered" => true}}}
      ])

      task = Future.poll("test-request", config: config, sleep_fun: fn _ -> :ok end)
      {:ok, result} = Future.await(task)
      assert result["recovered"] == true
    end
  end

  describe "try_again response handling" do
    test "continues polling on try_again response", %{config: config} do
      set_mock_responses([
        {:ok,
         %{
           "type" => "try_again",
           "request_id" => "test-request",
           "queue_state" => "paused_rate_limit",
           "retry_after_ms" => 100
         }},
        {:ok, %{"status" => "completed", "result" => %{"done" => true}}}
      ])

      task = Future.poll("test-request", config: config, sleep_fun: fn _ -> :ok end)
      {:ok, result} = Future.await(task)
      assert result["done"] == true
    end

    test "emits queue state telemetry on state change", %{config: config} do
      test_pid = self()

      :telemetry.attach(
        "test-queue-state-#{:erlang.unique_integer()}",
        [:tinkex, :queue, :state_change],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:queue_state_change, metadata})
        end,
        nil
      )

      set_mock_responses([
        {:ok,
         %{
           "type" => "try_again",
           "request_id" => "test-request",
           "queue_state" => "paused_rate_limit"
         }},
        {:ok, %{"status" => "completed", "result" => %{}}}
      ])

      task = Future.poll("test-request", config: config, sleep_fun: fn _ -> :ok end)
      Future.await(task)

      assert_receive {:queue_state_change, %{queue_state: :paused_rate_limit}}, 1000
    end
  end

  describe "HTTP error handling" do
    test "returns terminal error on 410 expired", %{config: config} do
      set_mock_responses({:error, Error.new(:api_status, "Gone", status: 410)})

      task = Future.poll("test-request", config: config, sleep_fun: fn _ -> :ok end)
      assert {:error, %Error{status: 410}} = Future.await(task)
    end

    test "retries on 5xx server errors", %{config: config} do
      set_mock_responses([
        {:error, Error.new(:api_status, "Server error", status: 500)},
        {:ok, %{"status" => "completed", "result" => %{"recovered" => true}}}
      ])

      task =
        Future.poll("test-request",
          config: config,
          sleep_fun: fn _ -> :ok end,
          poll_backoff: :none
        )

      {:ok, result} = Future.await(task)
      assert result["recovered"] == true
    end

    test "retries on connection errors", %{config: config} do
      set_mock_responses([
        {:error, Error.new(:api_connection, "Connection refused")},
        {:ok, %{"status" => "completed", "result" => %{"recovered" => true}}}
      ])

      task = Future.poll("test-request", config: config, sleep_fun: fn _ -> :ok end)
      {:ok, result} = Future.await(task)
      assert result["recovered"] == true
    end

    test "returns terminal error on 4xx client errors", %{config: config} do
      set_mock_responses({:error, Error.new(:api_status, "Bad request", status: 400)})

      task = Future.poll("test-request", config: config, sleep_fun: fn _ -> :ok end)
      assert {:error, %Error{status: 400}} = Future.await(task)
    end
  end

  describe "poll timeout" do
    test "returns error when poll_timeout exceeded", %{config: config} do
      set_mock_responses([
        {:ok, %{"status" => "pending"}},
        {:ok, %{"status" => "pending"}},
        {:ok, %{"status" => "pending"}}
      ])

      task =
        Future.poll("test-request",
          config: config,
          timeout: 1,
          sleep_fun: fn ms -> Process.sleep(ms) end
        )

      # The timeout should be exceeded quickly
      assert {:error, %Error{type: :api_timeout}} = Future.await(task, 5_000)
    end
  end

  describe "backoff calculation" do
    test "exponential backoff increases sleep time for pending responses", %{config: config} do
      set_mock_responses([
        {:ok, %{"status" => "pending"}},
        {:ok, %{"status" => "pending"}},
        {:ok, %{"status" => "pending"}},
        {:ok, %{"status" => "completed", "result" => %{}}}
      ])

      sleep_times = :ets.new(:sleep_times, [:public, :set])

      task =
        Future.poll("test-request",
          config: config,
          sleep_fun: fn ms ->
            :ets.insert(sleep_times, {System.monotonic_time(), ms})
          end
        )

      Future.await(task)

      times = :ets.tab2list(sleep_times) |> Enum.sort() |> Enum.map(&elem(&1, 1))
      :ets.delete(sleep_times)

      # Default exponential backoff: 1000, 2000, 4000, ... (capped at 30000)
      assert length(times) == 3
      assert Enum.at(times, 0) == 1000
      assert Enum.at(times, 1) == 2000
      assert Enum.at(times, 2) == 4000
    end
  end

  describe "queue state observer" do
    defmodule TestObserver do
      def on_queue_state_change(state, metadata) do
        send(metadata[:test_pid], {:observer_called, state, metadata})
      end
    end

    test "notifies observer on queue state change", %{config: config} do
      config = %{config | user_metadata: %{test_pid: self()}}

      set_mock_responses([
        {:ok,
         %{
           "type" => "try_again",
           "request_id" => "test-request",
           "queue_state" => "active"
         }},
        {:ok, %{"status" => "completed", "result" => %{}}}
      ])

      task =
        Future.poll("test-request",
          config: config,
          sleep_fun: fn _ -> :ok end,
          queue_state_observer: TestObserver
        )

      Future.await(task)

      assert_receive {:observer_called, :active, metadata}, 1000
      assert metadata[:request_id] == "test-request"
    end
  end
end
