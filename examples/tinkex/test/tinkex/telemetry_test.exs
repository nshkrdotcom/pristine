defmodule Tinkex.TelemetryTest do
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry
  alias Tinkex.Config

  import ExUnit.CaptureLog

  describe "attach_logger/1" do
    test "attaches handler and returns handler_id" do
      handler_id = Telemetry.attach_logger()

      assert is_binary(handler_id)
      assert String.starts_with?(handler_id, "tinkex-telemetry-")

      # Clean up
      :ok = Telemetry.detach(handler_id)
    end

    test "accepts custom handler_id" do
      handler_id = Telemetry.attach_logger(handler_id: "custom-handler-123")

      assert handler_id == "custom-handler-123"

      # Clean up
      :ok = Telemetry.detach(handler_id)
    end

    test "logs HTTP request start events" do
      handler_id = Telemetry.attach_logger(level: :info)

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:tinkex, :http, :request, :start],
            %{system_time: System.system_time()},
            %{
              method: "POST",
              path: "/api/v1/test",
              pool_type: :default,
              base_url: "http://localhost"
            }
          )
        end)

      assert log =~ "HTTP POST /api/v1/test start"
      assert log =~ "pool=default"
      assert log =~ "base=http://localhost"

      :ok = Telemetry.detach(handler_id)
    end

    test "logs HTTP request stop events" do
      handler_id = Telemetry.attach_logger(level: :info)

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:tinkex, :http, :request, :stop],
            %{duration: System.convert_time_unit(100, :millisecond, :native)},
            %{
              method: "POST",
              path: "/api/v1/test",
              result: 200,
              retry_count: 0,
              base_url: "http://localhost"
            }
          )
        end)

      assert log =~ "HTTP POST /api/v1/test 200"
      assert log =~ ~r/in \d+ms/
      assert log =~ "retries=0"

      :ok = Telemetry.detach(handler_id)
    end

    test "logs HTTP request exception events" do
      handler_id = Telemetry.attach_logger(level: :info)

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:tinkex, :http, :request, :exception],
            %{duration: System.convert_time_unit(50, :millisecond, :native)},
            %{method: "POST", path: "/api/v1/test", reason: :timeout}
          )
        end)

      assert log =~ "HTTP POST /api/v1/test exception"
      assert log =~ "reason=:timeout"

      :ok = Telemetry.detach(handler_id)
    end

    test "logs queue state change events" do
      handler_id = Telemetry.attach_logger(level: :info)

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:tinkex, :queue, :state_change],
            %{},
            %{queue_state: :active, request_id: "req-123"}
          )
        end)

      assert log =~ "Queue state changed to active"
      assert log =~ "request_id=req-123"

      :ok = Telemetry.detach(handler_id)
    end

    test "accepts custom log level" do
      handler_id = Telemetry.attach_logger(level: :debug)

      log =
        capture_log([level: :debug], fn ->
          :telemetry.execute(
            [:tinkex, :http, :request, :start],
            %{system_time: System.system_time()},
            %{method: "GET", path: "/test", pool_type: :default, base_url: "http://localhost"}
          )
        end)

      assert log =~ "HTTP GET /test start"

      :ok = Telemetry.detach(handler_id)
    end
  end

  describe "detach/1" do
    test "detaches handler and returns :ok" do
      handler_id = Telemetry.attach_logger()

      assert :ok = Telemetry.detach(handler_id)
    end

    test "returns error for unknown handler" do
      assert {:error, :not_found} = Telemetry.detach("non-existent-handler")
    end
  end

  describe "init/1" do
    test "starts reporter when enabled" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Telemetry.init(
          session_id: "init-test-session",
          config: config,
          enabled?: true,
          telemetry_opts: [attach_events?: false]
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "returns :ignore when disabled via option" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      assert :ignore =
               Telemetry.init(
                 session_id: "disabled-session",
                 config: config,
                 enabled?: false
               )
    end

    test "returns :ignore when disabled via config" do
      config =
        Config.new(
          api_key: "tml-test-key",
          base_url: "http://localhost:9999",
          telemetry_enabled?: false
        )

      assert :ignore =
               Telemetry.init(
                 session_id: "disabled-config-session",
                 config: config
               )
    end

    test "returns error for missing session_id" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      assert {:error, {:missing_required_option, :session_id}} =
               Telemetry.init(config: config)
    end

    test "returns error for missing config" do
      assert {:error, {:missing_required_option, :config}} =
               Telemetry.init(session_id: "test-session")
    end

    test "passes telemetry_opts to reporter" do
      config = Config.new(api_key: "tml-test-key", base_url: "http://localhost:9999")

      {:ok, pid} =
        Telemetry.init(
          session_id: "opts-test-session",
          config: config,
          enabled?: true,
          telemetry_opts: [
            attach_events?: false,
            flush_interval_ms: 5_000,
            max_queue_size: 500
          ]
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
end
