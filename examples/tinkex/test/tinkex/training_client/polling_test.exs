defmodule Tinkex.TrainingClient.PollingTest do
  use ExUnit.Case, async: true

  alias Tinkex.TrainingClient.Polling
  alias Tinkex.Error

  defmodule MockFutureModule do
    def await(%Task{} = task, _timeout) do
      Task.await(task)
    end

    def poll(future, _opts) do
      Task.async(fn -> {:ok, future} end)
    end
  end

  describe "await_forward_backward_results/2" do
    test "returns empty list for empty tasks" do
      assert {:ok, []} = Polling.await_forward_backward_results([], MockFutureModule)
    end

    test "awaits single task and converts result" do
      # ForwardBackwardOutput has loss_fn_output_type, loss_fn_outputs, metrics fields
      task =
        Task.async(fn ->
          {:ok,
           %{
             "loss_fn_output_type" => "cross_entropy",
             "loss_fn_outputs" => [],
             "metrics" => %{"loss" => 0.5}
           }}
        end)

      result = Polling.await_forward_backward_results([task], MockFutureModule)
      assert {:ok, [output]} = result
      assert output.loss_fn_output_type == "cross_entropy"
    end

    test "awaits multiple tasks in order" do
      task1 =
        Task.async(fn ->
          {:ok, %{"loss_fn_output_type" => "cross_entropy", "metrics" => %{"loss" => 0.1}}}
        end)

      task2 =
        Task.async(fn ->
          {:ok, %{"loss_fn_output_type" => "cross_entropy", "metrics" => %{"loss" => 0.2}}}
        end)

      result = Polling.await_forward_backward_results([task1, task2], MockFutureModule)
      assert {:ok, [out1, out2]} = result
      assert out1.metrics["loss"] == 0.1
      assert out2.metrics["loss"] == 0.2
    end

    test "returns error and kills remaining tasks on failure" do
      task1 = Task.async(fn -> {:error, Error.new(:request_failed, "test error")} end)
      task2 = Task.async(fn -> Process.sleep(5000) end)

      result = Polling.await_forward_backward_results([task1, task2], MockFutureModule)
      assert {:error, %Error{type: :request_failed}} = result
    end
  end

  describe "await_forward_results/2" do
    test "returns empty list for empty tasks" do
      assert {:ok, []} = Polling.await_forward_results([], MockFutureModule)
    end

    test "awaits forward results" do
      task =
        Task.async(fn ->
          {:ok, %{"loss_fn_output_type" => "cross_entropy", "metrics" => %{"loss" => 1.0}}}
        end)

      assert {:ok, [output]} = Polling.await_forward_results([task], MockFutureModule)
      assert output.metrics["loss"] == 1.0
    end
  end

  describe "await_forward_results_for_custom_loss/2" do
    test "returns empty list for empty tasks" do
      assert {:ok, []} = Polling.await_forward_results_for_custom_loss([], MockFutureModule)
    end

    test "awaits custom loss forward results" do
      task =
        Task.async(fn ->
          {:ok,
           %{"loss_fn_output_type" => "custom", "metrics" => %{"loss" => 2.5, "custom" => 1.0}}}
        end)

      assert {:ok, [output]} =
               Polling.await_forward_results_for_custom_loss([task], MockFutureModule)

      assert output.metrics["loss"] == 2.5
    end
  end

  describe "unlink_task/1" do
    test "unlinks task from current process" do
      task = Task.async(fn -> :ok end)

      assert :ok = Polling.unlink_task(task)
      # Task should still complete normally
      assert :ok = Task.await(task)
    end

    test "handles non-task values gracefully" do
      assert :ok = Polling.unlink_task(nil)
      assert :ok = Polling.unlink_task(:not_a_task)
      assert :ok = Polling.unlink_task(%{})
    end
  end

  describe "safe_await/3" do
    test "returns ok result from successful await" do
      task = Task.async(fn -> {:ok, "success"} end)

      assert {:ok, "success"} = Polling.safe_await(MockFutureModule, task, 5000)
    end

    test "returns error result from failed await" do
      task = Task.async(fn -> {:error, Error.new(:test, "test")} end)

      assert {:error, %Error{}} = Polling.safe_await(MockFutureModule, task, 5000)
    end

    test "wraps exceptions in error" do
      defmodule FailingFutureModule do
        def await(_task, _timeout) do
          raise "test exception"
        end
      end

      task = Task.async(fn -> :ok end)

      result = Polling.safe_await(FailingFutureModule, task, 5000)
      assert {:error, %Error{type: :request_failed}} = result

      # Clean up the task
      Task.shutdown(task)
    end
  end

  describe "poll_opts_with_type/3" do
    test "adds tinker_request_type to options" do
      state = %{
        telemetry_metadata: %{session_id: "sess-123"},
        model_id: "model-456",
        config: %{}
      }

      opts = Polling.poll_opts_with_type(state, [], "ForwardBackward")

      assert Keyword.get(opts, :tinker_request_type) == "ForwardBackward"
    end
  end

  describe "poll_opts/2" do
    test "builds poll options from state" do
      state = %{
        telemetry_metadata: %{session_id: "sess-123"},
        model_id: "model-456",
        config: %{timeout: 60_000}
      }

      opts = Polling.poll_opts(state, timeout: 30_000)

      assert Keyword.get(opts, :config) == %{timeout: 60_000}
      # default polling timeout
      assert Keyword.get(opts, :http_timeout) == 45_000
      assert Keyword.get(opts, :queue_state_observer) == Tinkex.TrainingClient.Observer

      telemetry = Keyword.get(opts, :telemetry_metadata)
      assert telemetry[:session_id] == "sess-123"
      assert telemetry[:model_id] == "model-456"
    end

    test "allows overriding queue_state_observer" do
      state = %{
        telemetry_metadata: %{},
        model_id: "model-123",
        config: %{}
      }

      opts = Polling.poll_opts(state, queue_state_observer: MyCustomObserver)

      assert Keyword.get(opts, :queue_state_observer) == MyCustomObserver
    end

    test "allows overriding http_timeout" do
      state = %{
        telemetry_metadata: %{},
        model_id: "model-123",
        config: %{}
      }

      opts = Polling.poll_opts(state, http_timeout: 10_000)

      assert Keyword.get(opts, :http_timeout) == 10_000
    end
  end
end
