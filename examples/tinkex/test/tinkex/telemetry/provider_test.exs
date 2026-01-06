defmodule Tinkex.Telemetry.ProviderTest do
  @moduledoc """
  Tests for the Telemetry.Provider behaviour.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Provider

  # Test module that uses Provider with default implementation
  defmodule DefaultProvider do
    use Provider
  end

  # Test module that overrides get_telemetry
  defmodule CustomProvider do
    use Provider

    @impl Provider
    def get_telemetry do
      :custom_reporter_pid
    end
  end

  # Test module with stateful telemetry
  defmodule StatefulProvider do
    use Provider

    def start_link(reporter_pid) do
      Agent.start_link(fn -> reporter_pid end, name: __MODULE__)
    end

    @impl Provider
    def get_telemetry do
      try do
        Agent.get(__MODULE__, & &1)
      catch
        :exit, _ -> nil
      end
    end
  end

  describe "behaviour definition" do
    test "defines get_telemetry/0 callback" do
      # Verify the behaviour is defined and accessible
      callbacks = Provider.behaviour_info(:callbacks)
      assert {:get_telemetry, 0} in callbacks
    end
  end

  describe "__using__/1 macro" do
    test "provides default get_telemetry/0 implementation returning nil" do
      assert DefaultProvider.get_telemetry() == nil
    end

    test "allows overriding get_telemetry/0" do
      assert CustomProvider.get_telemetry() == :custom_reporter_pid
    end

    test "module implements Provider behaviour" do
      # The module should compile without warnings about missing callbacks
      behaviours = DefaultProvider.__info__(:attributes)[:behaviour]
      assert Provider in behaviours
    end
  end

  describe "stateful provider" do
    setup do
      # Start the stateful provider with a fake reporter pid
      {:ok, agent} = StatefulProvider.start_link(self())

      on_exit(fn ->
        if Process.alive?(agent) do
          Agent.stop(agent)
        end
      end)

      :ok
    end

    test "returns configured reporter pid" do
      assert StatefulProvider.get_telemetry() == self()
    end
  end

  describe "provider integration" do
    test "provider can return pid or nil" do
      # Default returns nil
      assert is_nil(DefaultProvider.get_telemetry()) or is_pid(DefaultProvider.get_telemetry())

      # Custom returns an atom (simulating pid for test)
      result = CustomProvider.get_telemetry()
      assert result != nil
    end
  end
end
