defmodule Tinkex.SamplingRegistryTest do
  use ExUnit.Case, async: false

  alias Tinkex.SamplingRegistry

  setup do
    # Ensure the registry is running (app should have started it)
    registry_pid =
      case Process.whereis(SamplingRegistry) do
        nil ->
          {:ok, pid} = SamplingRegistry.start_link()
          pid

        pid ->
          pid
      end

    true = Process.alive?(registry_pid)

    # Each test uses unique spawned PIDs, so no cross-test pollution
    # The registry cleans up entries when monitored processes exit

    %{registry: registry_pid}
  end

  describe "start_link/1" do
    test "starts the registry", %{registry: pid} do
      # Registry was started in setup
      assert Process.alive?(pid)
    end

    test "creates ETS table" do
      # ETS table should exist (created by setup)
      assert :ets.whereis(:tinkex_sampling_clients) != :undefined
    end

    test "accepts custom name" do
      name = :"test_registry_custom_#{System.unique_integer([:positive])}"
      {:ok, pid} = SamplingRegistry.start_link(name: name)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "register/2" do
    test "registers a process with config" do
      # Create a test process
      test_pid = spawn(fn -> Process.sleep(10_000) end)

      config = %{model: "gpt-4", temperature: 0.7}
      assert :ok = SamplingRegistry.register(test_pid, config)

      # Verify it's in ETS
      assert {:ok, ^config} = SamplingRegistry.get_config(test_pid)

      Process.exit(test_pid, :kill)
    end

    test "allows registering multiple processes" do
      pid1 = spawn(fn -> Process.sleep(10_000) end)
      pid2 = spawn(fn -> Process.sleep(10_000) end)

      config1 = %{model: "gpt-4"}
      config2 = %{model: "gpt-3.5-turbo"}

      assert :ok = SamplingRegistry.register(pid1, config1)
      assert :ok = SamplingRegistry.register(pid2, config2)

      assert {:ok, ^config1} = SamplingRegistry.get_config(pid1)
      assert {:ok, ^config2} = SamplingRegistry.get_config(pid2)

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  describe "get_config/1" do
    test "returns config for registered process" do
      test_pid = spawn(fn -> Process.sleep(10_000) end)
      config = %{model: "gpt-4"}

      SamplingRegistry.register(test_pid, config)
      assert {:ok, ^config} = SamplingRegistry.get_config(test_pid)

      Process.exit(test_pid, :kill)
    end

    test "returns :error for unregistered process" do
      unregistered_pid = spawn(fn -> :ok end)
      Process.sleep(10)

      assert :error = SamplingRegistry.get_config(unregistered_pid)
    end
  end

  describe "list_pids/0" do
    test "returns empty list when no processes registered" do
      assert SamplingRegistry.list_pids() == []
    end

    test "returns list of registered PIDs" do
      pid1 = spawn(fn -> Process.sleep(10_000) end)
      pid2 = spawn(fn -> Process.sleep(10_000) end)

      SamplingRegistry.register(pid1, %{})
      SamplingRegistry.register(pid2, %{})

      pids = SamplingRegistry.list_pids()
      assert length(pids) == 2
      assert pid1 in pids
      assert pid2 in pids

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  describe "automatic cleanup on process exit" do
    test "cleans up ETS entry when registered process exits" do
      test_pid = spawn(fn -> Process.sleep(10_000) end)
      config = %{model: "gpt-4"}

      SamplingRegistry.register(test_pid, config)
      assert {:ok, ^config} = SamplingRegistry.get_config(test_pid)

      # Kill the process
      Process.exit(test_pid, :kill)

      # Wait for DOWN message to be processed
      Process.sleep(50)

      # Config should be cleaned up
      assert :error = SamplingRegistry.get_config(test_pid)
    end

    test "cleans up correct entry when one of multiple processes exits" do
      pid1 = spawn(fn -> Process.sleep(10_000) end)
      pid2 = spawn(fn -> Process.sleep(10_000) end)

      config1 = %{model: "gpt-4"}
      config2 = %{model: "gpt-3.5-turbo"}

      SamplingRegistry.register(pid1, config1)
      SamplingRegistry.register(pid2, config2)

      # Kill pid1
      Process.exit(pid1, :kill)
      Process.sleep(50)

      # pid1's config should be gone
      assert :error = SamplingRegistry.get_config(pid1)

      # pid2's config should still exist
      assert {:ok, ^config2} = SamplingRegistry.get_config(pid2)

      Process.exit(pid2, :kill)
    end
  end

  describe "process monitoring" do
    test "handles normal process termination" do
      parent = self()

      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end

          send(parent, :stopped)
        end)

      SamplingRegistry.register(test_pid, %{})
      assert {:ok, _} = SamplingRegistry.get_config(test_pid)

      send(test_pid, :stop)
      assert_receive :stopped

      Process.sleep(50)
      assert :error = SamplingRegistry.get_config(test_pid)
    end

    test "handles process crash" do
      test_pid =
        spawn(fn ->
          receive do
            :crash -> raise "intentional crash"
          end
        end)

      SamplingRegistry.register(test_pid, %{})
      assert {:ok, _} = SamplingRegistry.get_config(test_pid)

      send(test_pid, :crash)
      Process.sleep(50)

      assert :error = SamplingRegistry.get_config(test_pid)
    end
  end
end
