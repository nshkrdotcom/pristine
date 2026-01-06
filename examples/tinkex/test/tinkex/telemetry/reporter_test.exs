defmodule Tinkex.Telemetry.ReporterTest do
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Reporter
  alias Tinkex.Config

  describe "start_link/1" do
    test "starts reporter with required options" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      assert {:ok, pid} =
               Reporter.start_link(
                 session_id: "test-session-1",
                 config: config,
                 attach_events?: false,
                 enabled: true
               )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "returns :ignore when disabled via option" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      assert :ignore =
               Reporter.start_link(
                 session_id: "disabled-test",
                 config: config,
                 enabled: false
               )
    end

    test "returns :ignore when telemetry disabled in config" do
      config =
        Config.new(
          api_key: "tml-test-key",
          base_url: "http://localhost:9999",
          telemetry_enabled?: false
        )

      assert :ignore =
               Reporter.start_link(
                 session_id: "disabled-config-test",
                 config: config
               )
    end

    test "supports custom flush_interval_ms" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Reporter.start_link(
          session_id: "custom-interval",
          config: config,
          flush_interval_ms: 5_000,
          attach_events?: false,
          enabled: true
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "log/4" do
    test "logs event and returns true" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Reporter.start_link(
          session_id: "log-test",
          config: config,
          attach_events?: false,
          enabled: true
        )

      assert Reporter.log(pid, "test.event", %{foo: "bar"}) == true
      assert Reporter.log(pid, "test.event.2", %{}, :warning) == true

      GenServer.stop(pid)
    end

    test "returns false for nil pid" do
      assert Reporter.log(nil, "event", %{}) == false
    end

    test "returns false for non-existent pid" do
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(10)
      assert Reporter.log(dead_pid, "event", %{}) == false
    end
  end

  describe "log_exception/3" do
    test "logs exception and returns true" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Reporter.start_link(
          session_id: "exception-test",
          config: config,
          attach_events?: false,
          enabled: true
        )

      exception = RuntimeError.exception("test error")
      assert Reporter.log_exception(pid, exception) == true
      assert Reporter.log_exception(pid, exception, :warning) == true

      GenServer.stop(pid)
    end

    test "returns false for nil pid" do
      exception = RuntimeError.exception("test")
      assert Reporter.log_exception(nil, exception) == false
    end
  end

  describe "log_fatal_exception/3" do
    test "logs fatal exception and returns true" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Reporter.start_link(
          session_id: "fatal-test",
          config: config,
          attach_events?: false,
          enabled: true
        )

      exception = RuntimeError.exception("fatal error")
      assert Reporter.log_fatal_exception(pid, exception) == true

      GenServer.stop(pid)
    end

    test "returns false for nil pid" do
      exception = RuntimeError.exception("test")
      assert Reporter.log_fatal_exception(nil, exception) == false
    end
  end

  describe "flush/2" do
    test "flushes events and returns :ok" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Reporter.start_link(
          session_id: "flush-test",
          config: config,
          attach_events?: false,
          enabled: true
        )

      Reporter.log(pid, "test.event", %{})
      assert :ok = Reporter.flush(pid)

      GenServer.stop(pid)
    end

    test "supports sync option" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Reporter.start_link(
          session_id: "sync-flush-test",
          config: config,
          attach_events?: false,
          enabled: true
        )

      Reporter.log(pid, "test.event", %{})
      assert :ok = Reporter.flush(pid, sync?: true)

      GenServer.stop(pid)
    end

    test "returns false for nil pid" do
      assert Reporter.flush(nil) == false
    end
  end

  describe "wait_until_drained/2" do
    test "returns true when queue is empty after flush" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Reporter.start_link(
          session_id: "drain-test",
          config: config,
          attach_events?: false,
          enabled: true
        )

      # Flush to send initial session_start event
      :ok = Reporter.flush(pid, sync?: true)

      # After flush, should be drained
      assert Reporter.wait_until_drained(pid, 1_000) == true

      GenServer.stop(pid)
    end

    test "returns false for nil pid" do
      assert Reporter.wait_until_drained(nil) == false
    end
  end

  describe "stop/2" do
    test "stops reporter gracefully" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Reporter.start_link(
          session_id: "stop-test",
          config: config,
          attach_events?: false,
          enabled: true
        )

      assert Process.alive?(pid)
      assert :ok = Reporter.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end

    test "returns false for nil pid" do
      assert Reporter.stop(nil) == false
    end
  end

  describe "nil pid handling" do
    test "all public functions return false for nil pid" do
      assert Reporter.log(nil, "event", %{}) == false
      assert Reporter.log_exception(nil, RuntimeError.exception("test")) == false
      assert Reporter.log_fatal_exception(nil, RuntimeError.exception("test")) == false
      assert Reporter.flush(nil) == false
      assert Reporter.stop(nil) == false
      assert Reporter.wait_until_drained(nil) == false
    end
  end
end
