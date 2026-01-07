defmodule Pristine.Adapters.Telemetry.FoundationTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Telemetry.Foundation, as: TelemetryAdapter

  defmodule TestHandler do
    def handle_event(event, measurements, metadata, %{test_pid: test_pid, tag: tag}) do
      send(test_pid, {tag, event, measurements, metadata})
    end
  end

  describe "emit/3" do
    test "emits telemetry event under [:pristine, event] prefix" do
      test_pid = self()
      ref = make_ref()
      handler_id = "test-emit-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:pristine, :test_emit],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, tag: :telemetry}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = TelemetryAdapter.emit(:test_emit, %{key: "value"}, %{duration: 100})

      assert_receive {:telemetry, [:pristine, :test_emit], %{duration: 100}, %{key: "value"}}
    end
  end

  describe "measure/3" do
    test "times function execution and returns result" do
      result =
        TelemetryAdapter.measure(:test_measure, %{key: "value"}, fn ->
          Process.sleep(10)
          :test_result
        end)

      assert result == :test_result
    end

    test "emits telemetry event with duration" do
      test_pid = self()
      ref = make_ref()
      handler_id = "test-measure-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:pristine, :test_measure_event],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, tag: :measure}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      TelemetryAdapter.measure(:test_measure_event, %{id: 123}, fn ->
        Process.sleep(10)
        :ok
      end)

      assert_receive {:measure, [:pristine, :test_measure_event], measurements, metadata}
      assert is_integer(measurements[:duration])
      # At least 10ms in native time (nanoseconds on most systems)
      assert measurements[:duration] >= 10_000_000
      assert metadata[:id] == 123
      refute Map.has_key?(metadata, :error)
    end

    test "emits event with error flag when function raises" do
      test_pid = self()
      ref = make_ref()
      handler_id = "test-measure-error-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:pristine, :test_measure_error],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, tag: :measure}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert_raise RuntimeError, "test error", fn ->
        TelemetryAdapter.measure(:test_measure_error, %{op: "test"}, fn ->
          raise "test error"
        end)
      end

      assert_receive {:measure, [:pristine, :test_measure_error], measurements, metadata}
      assert is_integer(measurements[:duration])
      assert metadata[:error] == true
      assert metadata[:op] == "test"
    end
  end

  describe "emit_counter/2" do
    test "emits counter event with count: 1" do
      test_pid = self()
      ref = make_ref()
      handler_id = "test-counter-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:pristine, :test_counter],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, tag: :counter}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = TelemetryAdapter.emit_counter(:test_counter, %{type: "request"})

      assert_receive {:counter, [:pristine, :test_counter], %{count: 1}, %{type: "request"}}
    end
  end

  describe "emit_gauge/3" do
    test "emits gauge event with value" do
      test_pid = self()
      ref = make_ref()
      handler_id = "test-gauge-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:pristine, :test_gauge],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, tag: :gauge}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = TelemetryAdapter.emit_gauge(:test_gauge, 42.5, %{metric: "cpu"})

      assert_receive {:gauge, [:pristine, :test_gauge], %{value: 42.5}, %{metric: "cpu"}}
    end

    test "handles integer values" do
      test_pid = self()
      ref = make_ref()
      handler_id = "test-gauge-int-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:pristine, :test_gauge_int],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, tag: :gauge}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = TelemetryAdapter.emit_gauge(:test_gauge_int, 100, %{metric: "count"})

      assert_receive {:gauge, [:pristine, :test_gauge_int], %{value: 100}, %{metric: "count"}}
    end

    test "handles negative values" do
      test_pid = self()
      ref = make_ref()
      handler_id = "test-gauge-neg-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:pristine, :test_gauge_neg],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, tag: :gauge}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = TelemetryAdapter.emit_gauge(:test_gauge_neg, -10, %{metric: "temperature"})

      assert_receive {:gauge, [:pristine, :test_gauge_neg], %{value: -10},
                      %{metric: "temperature"}}
    end
  end
end
