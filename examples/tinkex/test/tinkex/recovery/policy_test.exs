defmodule Tinkex.Recovery.PolicyTest do
  use ExUnit.Case, async: true

  alias Tinkex.Recovery.Policy

  describe "new/1" do
    test "returns default struct when given nil" do
      policy = Policy.new(nil)

      assert policy.enabled == false
      assert policy.max_attempts == 3
      assert policy.backoff_ms == 5_000
      assert policy.max_backoff_ms == 60_000
      assert policy.poll_interval_ms == 30_000
      assert policy.checkpoint_strategy == :latest
      assert policy.restore_optimizer == true
      assert policy.on_recovery == nil
      assert policy.on_failure == nil
    end

    test "returns same struct when given a Policy struct" do
      original = %Policy{enabled: true, max_attempts: 5}
      policy = Policy.new(original)

      assert policy == original
    end

    test "builds from keyword list" do
      policy =
        Policy.new(
          enabled: true,
          max_attempts: 10,
          backoff_ms: 1_000,
          checkpoint_strategy: :latest
        )

      assert policy.enabled == true
      assert policy.max_attempts == 10
      assert policy.backoff_ms == 1_000
      assert policy.checkpoint_strategy == :latest
    end

    test "builds from map with atom keys" do
      policy =
        Policy.new(%{
          enabled: true,
          max_attempts: 5,
          restore_optimizer: false
        })

      assert policy.enabled == true
      assert policy.max_attempts == 5
      assert policy.restore_optimizer == false
    end

    test "builds from map with string keys" do
      policy =
        Policy.new(%{
          "enabled" => true,
          "max_attempts" => 7,
          "poll_interval_ms" => 10_000
        })

      assert policy.enabled == true
      assert policy.max_attempts == 7
      assert policy.poll_interval_ms == 10_000
    end

    test "ignores unknown keys" do
      policy = Policy.new(enabled: true, unknown_key: "value", another_unknown: 123)

      assert policy.enabled == true
      assert policy.max_attempts == 3
    end

    test "falls back to defaults for invalid boolean values" do
      policy = Policy.new(enabled: "not a boolean", restore_optimizer: 123)

      assert policy.enabled == false
      assert policy.restore_optimizer == true
    end

    test "falls back to defaults for invalid positive integer values" do
      policy =
        Policy.new(
          max_attempts: -5,
          backoff_ms: 0,
          max_backoff_ms: "string",
          poll_interval_ms: nil
        )

      assert policy.max_attempts == 3
      assert policy.backoff_ms == 5_000
      assert policy.max_backoff_ms == 60_000
      assert policy.poll_interval_ms == 30_000
    end

    test "accepts :latest checkpoint strategy" do
      policy = Policy.new(checkpoint_strategy: :latest)
      assert policy.checkpoint_strategy == :latest
    end

    test "accepts :best checkpoint strategy" do
      policy = Policy.new(checkpoint_strategy: :best)
      assert policy.checkpoint_strategy == :best
    end

    test "accepts {:specific, path} checkpoint strategy" do
      policy = Policy.new(checkpoint_strategy: {:specific, "tinker://run/checkpoint"})
      assert policy.checkpoint_strategy == {:specific, "tinker://run/checkpoint"}
    end

    test "normalizes string checkpoint strategies" do
      assert Policy.new(checkpoint_strategy: "latest").checkpoint_strategy == :latest
      assert Policy.new(checkpoint_strategy: "LATEST").checkpoint_strategy == :latest
      assert Policy.new(checkpoint_strategy: "best").checkpoint_strategy == :best
      assert Policy.new(checkpoint_strategy: "BEST").checkpoint_strategy == :best
    end

    test "falls back to :latest for invalid checkpoint strategy" do
      assert Policy.new(checkpoint_strategy: :invalid).checkpoint_strategy == :latest
      assert Policy.new(checkpoint_strategy: "unknown").checkpoint_strategy == :latest
      assert Policy.new(checkpoint_strategy: 123).checkpoint_strategy == :latest
    end

    test "accepts on_recovery callback with arity 3" do
      callback = fn _old_pid, _new_pid, _checkpoint -> :ok end
      policy = Policy.new(on_recovery: callback)
      assert policy.on_recovery == callback
    end

    test "rejects on_recovery callback with wrong arity" do
      callback = fn _arg -> :ok end
      policy = Policy.new(on_recovery: callback)
      assert policy.on_recovery == nil
    end

    test "accepts on_failure callback with arity 2" do
      callback = fn _run_id, _reason -> :ok end
      policy = Policy.new(on_failure: callback)
      assert policy.on_failure == callback
    end

    test "rejects on_failure callback with wrong arity" do
      callback = fn -> :ok end
      policy = Policy.new(on_failure: callback)
      assert policy.on_failure == nil
    end
  end

  describe "struct" do
    test "has expected fields" do
      policy = %Policy{}

      assert Map.has_key?(policy, :enabled)
      assert Map.has_key?(policy, :max_attempts)
      assert Map.has_key?(policy, :backoff_ms)
      assert Map.has_key?(policy, :max_backoff_ms)
      assert Map.has_key?(policy, :poll_interval_ms)
      assert Map.has_key?(policy, :checkpoint_strategy)
      assert Map.has_key?(policy, :restore_optimizer)
      assert Map.has_key?(policy, :on_recovery)
      assert Map.has_key?(policy, :on_failure)
    end
  end
end
