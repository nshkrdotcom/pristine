defmodule Tinkex.LoggingTest do
  use ExUnit.Case, async: false

  alias Tinkex.Logging

  describe "maybe_set_level/1" do
    test "returns :ok for nil" do
      assert Logging.maybe_set_level(nil) == :ok
    end

    test "accepts :debug level" do
      assert Logging.maybe_set_level(:debug) == :ok
    end

    test "accepts :info level" do
      assert Logging.maybe_set_level(:info) == :ok
    end

    test "accepts :warn level" do
      assert Logging.maybe_set_level(:warn) == :ok
    end

    test "accepts :warning level" do
      assert Logging.maybe_set_level(:warning) == :ok
    end

    test "accepts :error level" do
      assert Logging.maybe_set_level(:error) == :ok
    end
  end

  describe "normalize_level/1" do
    test "converts :warn to :warning" do
      assert Logging.normalize_level(:warn) == :warning
    end

    test "preserves :debug" do
      assert Logging.normalize_level(:debug) == :debug
    end

    test "preserves :info" do
      assert Logging.normalize_level(:info) == :info
    end

    test "preserves :warning" do
      assert Logging.normalize_level(:warning) == :warning
    end

    test "preserves :error" do
      assert Logging.normalize_level(:error) == :error
    end
  end

  describe "process isolation" do
    test "uses process-level logging when isolated flag is set" do
      # Set the isolation flag
      Process.put(:logger_isolated, true)

      try do
        # Should use process-level logging
        assert Logging.maybe_set_level(:debug) == :ok
      after
        Process.delete(:logger_isolated)
      end
    end
  end
end
