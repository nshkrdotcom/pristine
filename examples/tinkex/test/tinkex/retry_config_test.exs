defmodule Tinkex.RetryConfigTest do
  @moduledoc """
  Tests for user-facing retry configuration.
  """
  use ExUnit.Case, async: true

  alias Tinkex.RetryConfig

  describe "new/1" do
    test "builds with defaults" do
      config = RetryConfig.new()

      assert config.max_retries == :infinity
      assert config.base_delay_ms == 500
      assert config.max_delay_ms == 10_000
      assert config.jitter_pct == 0.25
      assert config.progress_timeout_ms == 7_200_000
      assert config.max_connections == 1000
      assert config.enable_retry_logic == true
    end

    test "accepts keyword overrides" do
      config =
        RetryConfig.new(
          max_retries: 2,
          base_delay_ms: 100,
          max_delay_ms: 200,
          jitter_pct: 0.1,
          progress_timeout_ms: 5_000,
          max_connections: 5,
          enable_retry_logic: false
        )

      assert config.max_retries == 2
      assert config.base_delay_ms == 100
      assert config.max_delay_ms == 200
      assert config.jitter_pct == 0.1
      assert config.progress_timeout_ms == 5_000
      assert config.max_connections == 5
      assert config.enable_retry_logic == false
    end

    test "allows :infinity max_retries" do
      config = RetryConfig.new(max_retries: :infinity)
      assert config.max_retries == :infinity
    end

    test "allows zero max_retries" do
      config = RetryConfig.new(max_retries: 0)
      assert config.max_retries == 0
    end
  end

  describe "default/0" do
    test "returns default configuration" do
      config = RetryConfig.default()
      assert config == RetryConfig.new()
    end
  end

  describe "validate!/1" do
    test "raises on negative max_retries" do
      assert_raise ArgumentError, ~r/max_retries/, fn ->
        RetryConfig.new(max_retries: -1)
      end
    end

    test "raises on invalid max_retries atom" do
      assert_raise ArgumentError, ~r/max_retries/, fn ->
        RetryConfig.new(max_retries: :never)
      end
    end

    test "raises on zero base_delay_ms" do
      assert_raise ArgumentError, ~r/base_delay_ms/, fn ->
        RetryConfig.new(base_delay_ms: 0)
      end
    end

    test "raises on negative base_delay_ms" do
      assert_raise ArgumentError, ~r/base_delay_ms/, fn ->
        RetryConfig.new(base_delay_ms: -100)
      end
    end

    test "raises when max_delay_ms less than base_delay_ms" do
      assert_raise ArgumentError, ~r/max_delay_ms/, fn ->
        RetryConfig.new(base_delay_ms: 500, max_delay_ms: 100)
      end
    end

    test "raises on negative jitter_pct" do
      assert_raise ArgumentError, ~r/jitter_pct/, fn ->
        RetryConfig.new(jitter_pct: -0.1)
      end
    end

    test "raises on jitter_pct greater than 1.0" do
      assert_raise ArgumentError, ~r/jitter_pct/, fn ->
        RetryConfig.new(jitter_pct: 1.1)
      end
    end

    test "raises on zero progress_timeout_ms" do
      assert_raise ArgumentError, ~r/progress_timeout_ms/, fn ->
        RetryConfig.new(progress_timeout_ms: 0)
      end
    end

    test "raises on zero max_connections" do
      assert_raise ArgumentError, ~r/max_connections/, fn ->
        RetryConfig.new(max_connections: 0)
      end
    end

    test "raises on non-boolean enable_retry_logic" do
      assert_raise ArgumentError, ~r/enable_retry_logic/, fn ->
        RetryConfig.new(enable_retry_logic: :nope)
      end
    end
  end

  describe "to_handler_opts/1" do
    test "exports options for RetryHandler" do
      config =
        RetryConfig.new(
          max_retries: 4,
          base_delay_ms: 600,
          max_delay_ms: 1200,
          jitter_pct: 0.2,
          progress_timeout_ms: 10_000
        )

      opts = RetryConfig.to_handler_opts(config)

      assert opts[:max_retries] == 4
      assert opts[:base_delay_ms] == 600
      assert opts[:max_delay_ms] == 1200
      assert opts[:jitter_pct] == 0.2
      assert opts[:progress_timeout_ms] == 10_000
    end

    test "does not include max_connections or enable_retry_logic" do
      config = RetryConfig.new()
      opts = RetryConfig.to_handler_opts(config)

      refute Keyword.has_key?(opts, :max_connections)
      refute Keyword.has_key?(opts, :enable_retry_logic)
    end
  end
end
