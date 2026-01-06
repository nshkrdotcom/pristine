defmodule Tinkex.Recovery.ExecutorTest do
  use ExUnit.Case, async: true

  alias Tinkex.Recovery.{Executor, Policy}
  alias Tinkex.Types.Checkpoint

  defmodule MockServiceClient do
    @behaviour Tinkex.Recovery.ServiceClientBehaviour

    def create_rest_client(_pid) do
      {:ok, %{}}
    end

    def create_training_client_from_state(service_pid, path, _opts) do
      test_pid = :persistent_term.get({__MODULE__, service_pid}, nil)

      if test_pid do
        send(test_pid, {:client_created, service_pid, path, :without_optimizer})
      end

      {:ok, :new_training_client}
    end

    def create_training_client_from_state_with_optimizer(service_pid, path, _opts) do
      test_pid = :persistent_term.get({__MODULE__, service_pid}, nil)

      if test_pid do
        send(test_pid, {:client_created, service_pid, path, :with_optimizer})
      end

      {:ok, :new_training_client}
    end

    def set_test_pid(test_pid, service_ref) do
      :persistent_term.put({__MODULE__, service_ref}, test_pid)
    end

    def clear(service_ref) do
      :persistent_term.erase({__MODULE__, service_ref})
    end
  end

  defmodule FailingServiceClient do
    @behaviour Tinkex.Recovery.ServiceClientBehaviour

    def create_rest_client(_pid), do: {:ok, %{}}

    def create_training_client_from_state(_service_pid, _path, _opts) do
      {:error, :not_ready}
    end

    def create_training_client_from_state_with_optimizer(_service_pid, _path, _opts) do
      {:error, :not_ready}
    end
  end

  setup do
    service_pid = make_ref()
    MockServiceClient.set_test_pid(self(), service_pid)

    send_after = fn msg, _delay ->
      send(self(), msg)
      make_ref()
    end

    on_exit(fn ->
      MockServiceClient.clear(service_pid)
    end)

    %{send_after: send_after, service_pid: service_pid}
  end

  describe "start_link/1" do
    test "starts executor with defaults" do
      assert {:ok, pid} = Executor.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts executor with custom options" do
      assert {:ok, pid} =
               Executor.start_link(
                 max_concurrent: 5,
                 service_client_module: MockServiceClient
               )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "recover/5" do
    test "returns error when recovery is disabled", %{
      send_after: send_after,
      service_pid: service_pid
    } do
      {:ok, executor} =
        Executor.start_link(
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      policy = Policy.new(enabled: false)
      result = Executor.recover(executor, "run-123", service_pid, policy)

      assert result == {:error, :recovery_disabled}
      GenServer.stop(executor)
    end

    test "returns error for duplicate run_id", %{service_pid: service_pid} do
      # Use a send_after that doesn't immediately deliver messages
      # so the run stays in pending_retry
      send_after = fn msg, _delay ->
        # Don't immediately send - just return a ref
        make_ref()
      end

      {:ok, executor} =
        Executor.start_link(
          service_client_module: FailingServiceClient,
          send_after: send_after
        )

      policy = Policy.new(enabled: true, max_attempts: 5)
      checkpoint = %Checkpoint{tinker_path: "tinker://run/checkpoint"}

      assert :ok =
               Executor.recover(executor, "run-123", service_pid, policy,
                 last_checkpoint: checkpoint
               )

      # Wait for the first attempt to fail and enter pending_retry
      Process.sleep(50)

      # Now try to recover the same run - should fail
      assert {:error, :already_pending} =
               Executor.recover(executor, "run-123", service_pid, policy,
                 last_checkpoint: checkpoint
               )

      GenServer.stop(executor)
    end

    test "performs recovery with optimizer restore", %{
      send_after: send_after,
      service_pid: service_pid
    } do
      test_pid = self()

      policy =
        Policy.new(
          enabled: true,
          checkpoint_strategy: :latest,
          restore_optimizer: true
        )
        |> Map.put(:on_recovery, fn _old_pid, new_pid, checkpoint ->
          send(test_pid, {:recovered, new_pid, checkpoint})
          :ok
        end)

      {:ok, executor} =
        Executor.start_link(
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      checkpoint = %Checkpoint{tinker_path: "tinker://run/checkpoint"}

      assert :ok =
               Executor.recover(executor, "run-123", service_pid, policy,
                 last_checkpoint: checkpoint,
                 metadata: %{training_pid: :old_training}
               )

      assert_receive {:client_created, ^service_pid, "tinker://run/checkpoint", :with_optimizer}
      assert_receive {:recovered, :new_training_client, %Checkpoint{}}

      GenServer.stop(executor)
    end

    test "performs recovery without optimizer restore", %{
      send_after: send_after,
      service_pid: service_pid
    } do
      policy = Policy.new(enabled: true, restore_optimizer: false)

      {:ok, executor} =
        Executor.start_link(
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      checkpoint = %Checkpoint{tinker_path: "tinker://run/checkpoint"}

      assert :ok =
               Executor.recover(executor, "run-456", service_pid, policy,
                 last_checkpoint: checkpoint
               )

      assert_receive {:client_created, ^service_pid, "tinker://run/checkpoint",
                      :without_optimizer}

      GenServer.stop(executor)
    end

    test "emits telemetry events", %{send_after: send_after, service_pid: service_pid} do
      parent = self()

      :telemetry.attach_many(
        "test-recovery-telemetry",
        [
          [:tinkex, :recovery, :started],
          [:tinkex, :recovery, :checkpoint_selected],
          [:tinkex, :recovery, :client_created],
          [:tinkex, :recovery, :completed]
        ],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      policy = Policy.new(enabled: true)

      {:ok, executor} =
        Executor.start_link(
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      checkpoint = %Checkpoint{tinker_path: "tinker://run/checkpoint"}

      assert :ok =
               Executor.recover(executor, "run-789", service_pid, policy,
                 last_checkpoint: checkpoint
               )

      assert_receive {:telemetry, [:tinkex, :recovery, :started], _, %{run_id: "run-789"}}
      assert_receive {:telemetry, [:tinkex, :recovery, :checkpoint_selected], _, _}
      assert_receive {:telemetry, [:tinkex, :recovery, :client_created], _, _}
      assert_receive {:telemetry, [:tinkex, :recovery, :completed], _, _}

      :telemetry.detach("test-recovery-telemetry")
      GenServer.stop(executor)
    end

    test "returns error for missing checkpoint", %{
      send_after: send_after,
      service_pid: service_pid
    } do
      parent = self()

      :telemetry.attach(
        "test-recovery-failed",
        [:tinkex, :recovery, :failed],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      policy = Policy.new(enabled: true, max_attempts: 1)

      {:ok, executor} =
        Executor.start_link(
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      assert :ok = Executor.recover(executor, "run-no-checkpoint", service_pid, policy)

      assert_receive {:telemetry, [:tinkex, :recovery, :failed], _, %{error: :missing_checkpoint}}

      :telemetry.detach("test-recovery-failed")
      GenServer.stop(executor)
    end
  end

  describe "backoff and exhaustion" do
    test "backs off and emits exhausted after max attempts", %{service_pid: service_pid} do
      parent = self()

      # Custom send_after that immediately delivers the message to the executor
      # but also notifies the test
      send_after = fn msg, _delay ->
        send(parent, {:retry_scheduled, msg})
        send(self(), msg)
        make_ref()
      end

      :telemetry.attach_many(
        "test-recovery-exhausted",
        [
          [:tinkex, :recovery, :failed],
          [:tinkex, :recovery, :exhausted]
        ],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      policy =
        Policy.new(
          enabled: true,
          max_attempts: 2,
          backoff_ms: 1,
          max_backoff_ms: 1
        )
        |> Map.put(:on_failure, fn run_id, reason ->
          send(parent, {:failure_callback, run_id, reason})
          :ok
        end)

      {:ok, executor} =
        Executor.start_link(
          service_client_module: FailingServiceClient,
          send_after: send_after
        )

      checkpoint = %Checkpoint{tinker_path: "tinker://run/checkpoint"}

      assert :ok =
               Executor.recover(executor, "run-exhausted", service_pid, policy,
                 last_checkpoint: checkpoint
               )

      # First attempt fails, retry gets scheduled
      assert_receive {:telemetry, [:tinkex, :recovery, :failed], _, _}
      assert_receive {:retry_scheduled, {:retry, _entry}}

      # Second attempt fails and exhausts
      assert_receive {:telemetry, [:tinkex, :recovery, :exhausted], _, %{run_id: "run-exhausted"}}
      assert_receive {:failure_callback, "run-exhausted", :not_ready}

      :telemetry.detach("test-recovery-exhausted")
      GenServer.stop(executor)
    end
  end

  describe "specific checkpoint strategy" do
    test "uses specific checkpoint path", %{send_after: send_after, service_pid: service_pid} do
      policy =
        Policy.new(enabled: true, checkpoint_strategy: {:specific, "tinker://specific/path"})

      {:ok, executor} =
        Executor.start_link(
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      assert :ok = Executor.recover(executor, "run-specific", service_pid, policy)

      assert_receive {:client_created, ^service_pid, "tinker://specific/path", _}

      GenServer.stop(executor)
    end
  end
end
