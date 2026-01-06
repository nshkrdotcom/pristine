defmodule Tinkex.SamplingClientObservabilityTest do
  @moduledoc """
  Tests for SamplingClient queue state observability functions.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Tinkex.Config
  alias Tinkex.SamplingClient

  setup do
    # Use a unique client ID per test to avoid cross-test pollution
    test_id = :erlang.unique_integer([:positive])
    client_id = "sampler-observability-#{test_id}"

    config = Config.new(api_key: "tml-test-key", base_url: "https://api.test.com")
    client = SamplingClient.new(client_id, config)

    # Clear debounce state before AND after test
    SamplingClient.clear_queue_state_debounce(client)

    on_exit(fn ->
      SamplingClient.clear_queue_state_debounce(client)
    end)

    {:ok, config: config, client: client, client_id: client_id}
  end

  describe "on_queue_state_change/2" do
    test "logs warning on paused_rate_limit state", %{client: client, client_id: client_id} do
      log =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client, :paused_rate_limit)
        end)

      assert log =~ "Sampling is paused"
      assert log =~ client_id
      assert log =~ "concurrent sampler weights limit hit"
    end

    test "logs warning on paused_capacity state", %{client: client, client_id: client_id} do
      log =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client, :paused_capacity)
        end)

      assert log =~ "Sampling is paused"
      assert log =~ client_id
      assert log =~ "capacity"
    end

    test "does not log on active state", %{client: client} do
      log =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client, :active)
        end)

      assert log == ""
    end

    test "debounces repeated calls within interval", %{client: client} do
      # First call should log
      log1 =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client, :paused_rate_limit)
        end)

      assert log1 =~ "Sampling is paused"

      # Immediate second call should be debounced
      log2 =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client, :paused_rate_limit)
        end)

      assert log2 == ""
    end

    test "accepts optional metadata", %{client: client} do
      log =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client, :paused_rate_limit, %{
            request_id: "req-123",
            queue_state_reason: "custom reason"
          })
        end)

      # Should log with custom reason when provided
      assert log =~ "Sampling is paused"
    end

    test "uses server reason when provided in metadata", %{client: client} do
      log =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client, :paused_rate_limit, %{
            queue_state_reason: "Server is busy, please wait"
          })
        end)

      assert log =~ "Server is busy, please wait"
    end
  end

  describe "on_queue_state_change/3 with various queue states" do
    test "handles all QueueState values", %{client: client} do
      for state <- [:paused_rate_limit, :paused_capacity, :unknown] do
        SamplingClient.clear_queue_state_debounce(client)

        log =
          capture_log([level: :warning], fn ->
            SamplingClient.on_queue_state_change(client, state, %{
              queue_state_reason: "test reason for #{state}"
            })
          end)

        assert log =~ "test reason for #{state}"
      end
    end
  end

  describe "clear_queue_state_debounce/1" do
    test "clears debounce state allowing immediate log", %{client: client} do
      # First call logs
      log1 =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client, :paused_rate_limit)
        end)

      assert log1 =~ "Sampling is paused"

      # Clear debounce
      :ok = SamplingClient.clear_queue_state_debounce(client)

      # Should log again immediately after clear
      log2 =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client, :paused_rate_limit)
        end)

      assert log2 =~ "Sampling is paused"
    end

    test "returns :ok even when no debounce state exists", %{client: client} do
      assert :ok = SamplingClient.clear_queue_state_debounce(client)
    end

    test "is idempotent", %{client: client} do
      # Trigger a log to create debounce state
      capture_log([level: :warning], fn ->
        SamplingClient.on_queue_state_change(client, :paused_rate_limit)
      end)

      # Clear multiple times
      assert :ok = SamplingClient.clear_queue_state_debounce(client)
      assert :ok = SamplingClient.clear_queue_state_debounce(client)
      assert :ok = SamplingClient.clear_queue_state_debounce(client)
    end
  end

  describe "debounce key isolation" do
    test "different clients have independent debounce state", %{config: config} do
      # Use unique IDs for this test's clients
      test_id = :erlang.unique_integer([:positive])
      client1 = SamplingClient.new("sampler-iso-1-#{test_id}", config)
      client2 = SamplingClient.new("sampler-iso-2-#{test_id}", config)

      # Clear before test
      SamplingClient.clear_queue_state_debounce(client1)
      SamplingClient.clear_queue_state_debounce(client2)

      on_exit(fn ->
        SamplingClient.clear_queue_state_debounce(client1)
        SamplingClient.clear_queue_state_debounce(client2)
      end)

      # Both should log (independent debounce state)
      log1 =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client1, :paused_rate_limit)
        end)

      log2 =
        capture_log([level: :warning], fn ->
          SamplingClient.on_queue_state_change(client2, :paused_rate_limit)
        end)

      assert log1 =~ "sampler-iso-1-#{test_id}"
      assert log2 =~ "sampler-iso-2-#{test_id}"
    end
  end

  describe "integration with QueueStateObserver behaviour" do
    test "SamplingClient implements QueueStateObserver behaviour", %{client: _client} do
      # The on_queue_state_change function signature matches the behaviour
      assert function_exported?(SamplingClient, :on_queue_state_change, 2)
      assert function_exported?(SamplingClient, :on_queue_state_change, 3)
    end
  end
end
