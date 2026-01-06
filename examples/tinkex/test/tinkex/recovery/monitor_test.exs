defmodule Tinkex.Recovery.MonitorTest do
  use ExUnit.Case, async: true

  alias Tinkex.Recovery.{Monitor, Executor, Policy}
  alias Tinkex.Types.TrainingRun
  alias Tinkex.Config

  defmodule MockRestModule do
    @moduledoc false

    def get_training_run(_config, run_id) do
      case :persistent_term.get({__MODULE__, run_id}, :not_found) do
        :not_found -> {:error, :not_found}
        run -> {:ok, run}
      end
    end

    def set_run(run_id, run) do
      :persistent_term.put({__MODULE__, run_id}, run)
    end

    def clear(run_id) do
      :persistent_term.erase({__MODULE__, run_id})
    end
  end

  defmodule MockServiceClient do
    @behaviour Tinkex.Recovery.ServiceClientBehaviour

    def create_rest_client(service_pid) do
      case :persistent_term.get({__MODULE__, :rest_client, service_pid}, nil) do
        nil -> {:error, :not_configured}
        config -> {:ok, %{config: config}}
      end
    end

    def create_training_client_from_state(_service_pid, _path, _opts) do
      {:ok, :new_training_client}
    end

    def create_training_client_from_state_with_optimizer(_service_pid, _path, _opts) do
      {:ok, :new_training_client}
    end

    def set_rest_client(service_pid, config) do
      :persistent_term.put({__MODULE__, :rest_client, service_pid}, config)
    end

    def clear(service_pid) do
      :persistent_term.erase({__MODULE__, :rest_client, service_pid})
    end
  end

  defmodule MockExecutor do
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: opts[:name])
    end

    def init(_opts) do
      {:ok, %{recoveries: []}}
    end

    def get_recoveries(pid) do
      GenServer.call(pid, :get_recoveries)
    end

    def handle_call({:recover, run_id, service_pid, policy, opts}, _from, state) do
      test_pid = :persistent_term.get({__MODULE__, :test_pid}, nil)

      if test_pid do
        send(test_pid, {:recovery_requested, run_id, service_pid, policy, opts})
      end

      recovery = %{run_id: run_id, service_pid: service_pid, policy: policy, opts: opts}
      {:reply, :ok, %{state | recoveries: [recovery | state.recoveries]}}
    end

    def handle_call(:get_recoveries, _from, state) do
      {:reply, state.recoveries, state}
    end

    def set_test_pid(test_pid) do
      :persistent_term.put({__MODULE__, :test_pid}, test_pid)
    end

    def clear do
      :persistent_term.erase({__MODULE__, :test_pid})
    end
  end

  setup do
    service_pid = make_ref()
    config = %Config{api_key: "test-key", base_url: "https://test.api"}
    MockServiceClient.set_rest_client(service_pid, config)
    MockExecutor.set_test_pid(self())

    send_after = fn msg, _delay ->
      send(self(), msg)
      make_ref()
    end

    on_exit(fn ->
      MockServiceClient.clear(service_pid)
      MockExecutor.clear()
    end)

    %{service_pid: service_pid, config: config, send_after: send_after}
  end

  describe "start_link/1" do
    test "starts monitor with defaults" do
      assert {:ok, pid} = Monitor.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts monitor with custom policy" do
      policy = Policy.new(enabled: true, poll_interval_ms: 1000)

      assert {:ok, pid} = Monitor.start_link(policy: policy)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "monitor_run/4" do
    test "returns error when recovery is disabled", %{service_pid: service_pid} do
      {:ok, executor} = MockExecutor.start_link()
      {:ok, monitor} = Monitor.start_link(policy: %{enabled: false}, executor: executor)

      result = Monitor.monitor_run(monitor, "run-123", service_pid)

      assert result == {:error, :recovery_disabled}
      GenServer.stop(monitor)
      GenServer.stop(executor)
    end

    test "returns error when no executor configured", %{service_pid: service_pid} do
      {:ok, monitor} = Monitor.start_link(policy: %{enabled: true})

      result = Monitor.monitor_run(monitor, "run-123", service_pid)

      assert result == {:error, :no_executor}
      GenServer.stop(monitor)
    end

    test "successfully monitors a run", %{service_pid: service_pid} do
      parent = self()

      # Send_after that notifies parent and also delivers to monitor
      send_after = fn msg, _delay ->
        send(parent, {:poll_scheduled, msg})
        # Return a ref to simulate timer
        make_ref()
      end

      {:ok, executor} = MockExecutor.start_link()

      {:ok, monitor} =
        Monitor.start_link(
          policy: %{enabled: true, poll_interval_ms: 100},
          executor: executor,
          rest_module: MockRestModule,
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      result = Monitor.monitor_run(monitor, "run-123", service_pid, %{training_pid: :old_pid})

      assert result == :ok

      # Should schedule a poll
      assert_receive {:poll_scheduled, :poll}

      GenServer.stop(monitor)
      GenServer.stop(executor)
    end

    test "returns error when rest client creation fails", %{send_after: send_after} do
      unconfigured_pid = make_ref()
      {:ok, executor} = MockExecutor.start_link()

      {:ok, monitor} =
        Monitor.start_link(
          policy: %{enabled: true},
          executor: executor,
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      result = Monitor.monitor_run(monitor, "run-123", unconfigured_pid)

      assert result == {:error, :not_configured}
      GenServer.stop(monitor)
      GenServer.stop(executor)
    end
  end

  describe "stop_monitoring/2" do
    test "removes run from monitoring", %{service_pid: service_pid, send_after: send_after} do
      {:ok, executor} = MockExecutor.start_link()

      {:ok, monitor} =
        Monitor.start_link(
          policy: %{enabled: true},
          executor: executor,
          rest_module: MockRestModule,
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      :ok = Monitor.monitor_run(monitor, "run-123", service_pid)
      :ok = Monitor.stop_monitoring(monitor, "run-123")

      GenServer.stop(monitor)
      GenServer.stop(executor)
    end
  end

  describe "polling and recovery detection" do
    test "detects corrupted run and dispatches recovery", %{service_pid: service_pid} do
      parent = self()

      # Custom send_after that delivers to monitor immediately
      send_after = fn msg, _delay ->
        send(parent, {:poll_scheduled, msg})
        make_ref()
      end

      :telemetry.attach(
        "test-recovery-detected",
        [:tinkex, :recovery, :detected],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      corrupted_run = %TrainingRun{
        training_run_id: "run-corrupted",
        base_model: "test-model",
        model_owner: "test-owner",
        is_lora: false,
        last_request_time: DateTime.utc_now(),
        corrupted: true,
        last_checkpoint: %{tinker_path: "tinker://run/checkpoint"}
      }

      MockRestModule.set_run("run-corrupted", corrupted_run)

      {:ok, executor} = MockExecutor.start_link()

      {:ok, monitor} =
        Monitor.start_link(
          policy: %{enabled: true, poll_interval_ms: 10},
          executor: executor,
          rest_module: MockRestModule,
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      :ok = Monitor.monitor_run(monitor, "run-corrupted", service_pid)

      # Verify poll was scheduled
      assert_receive {:poll_scheduled, :poll}

      # Trigger the poll manually
      send(monitor, :poll)

      # Should detect corruption and dispatch recovery
      assert_receive {:telemetry, [:tinkex, :recovery, :detected], _, %{run_id: "run-corrupted"}}
      assert_receive {:recovery_requested, "run-corrupted", ^service_pid, %Policy{}, _opts}

      :telemetry.detach("test-recovery-detected")
      MockRestModule.clear("run-corrupted")
      GenServer.stop(monitor)
      GenServer.stop(executor)
    end

    test "does not dispatch recovery for non-corrupted run", %{service_pid: service_pid} do
      parent = self()

      send_after = fn msg, _delay ->
        send(parent, {:poll_scheduled, msg})
        make_ref()
      end

      healthy_run = %TrainingRun{
        training_run_id: "run-healthy",
        base_model: "test-model",
        model_owner: "test-owner",
        is_lora: false,
        last_request_time: DateTime.utc_now(),
        corrupted: false
      }

      MockRestModule.set_run("run-healthy", healthy_run)

      {:ok, executor} = MockExecutor.start_link()

      {:ok, monitor} =
        Monitor.start_link(
          policy: %{enabled: true, poll_interval_ms: 10},
          executor: executor,
          rest_module: MockRestModule,
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      :ok = Monitor.monitor_run(monitor, "run-healthy", service_pid)

      # Verify poll was scheduled
      assert_receive {:poll_scheduled, :poll}

      # Trigger the poll
      send(monitor, :poll)

      # Should not receive recovery request
      refute_receive {:recovery_requested, _, _, _, _}, 100

      MockRestModule.clear("run-healthy")
      GenServer.stop(monitor)
      GenServer.stop(executor)
    end

    test "emits poll_error telemetry on REST failure", %{service_pid: service_pid} do
      parent = self()

      send_after = fn msg, _delay ->
        send(parent, {:poll_scheduled, msg})
        make_ref()
      end

      :telemetry.attach(
        "test-poll-error",
        [:tinkex, :recovery, :poll_error],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Don't set up the run - will cause :not_found error
      {:ok, executor} = MockExecutor.start_link()

      {:ok, monitor} =
        Monitor.start_link(
          policy: %{enabled: true, poll_interval_ms: 10},
          executor: executor,
          rest_module: MockRestModule,
          service_client_module: MockServiceClient,
          send_after: send_after
        )

      :ok = Monitor.monitor_run(monitor, "run-missing", service_pid)

      # Verify poll was scheduled
      assert_receive {:poll_scheduled, :poll}

      # Trigger the poll
      send(monitor, :poll)

      # Should emit poll_error
      assert_receive {:telemetry, [:tinkex, :recovery, :poll_error], _, %{error: :not_found}}

      :telemetry.detach("test-poll-error")
      GenServer.stop(monitor)
      GenServer.stop(executor)
    end
  end
end
