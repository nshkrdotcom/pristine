defmodule Pristine.Adapters.Telemetry.FoundationTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Telemetry.Foundation, as: TelemetryAdapter

  describe "emit/3" do
    test "emits telemetry event under [:pristine, event] prefix" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-emit-#{inspect(ref)}",
        [:pristine, :test_emit],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      assert :ok = TelemetryAdapter.emit(:test_emit, %{key: "value"}, %{duration: 100})

      assert_receive {:telemetry, [:pristine, :test_emit], %{duration: 100}, %{key: "value"}}

      :telemetry.detach("test-emit-#{inspect(ref)}")
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

      :telemetry.attach(
        "test-measure-#{inspect(ref)}",
        [:pristine, :test_measure_event],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      TelemetryAdapter.measure(:test_measure_event, %{id: 123}, fn ->
        Process.sleep(10)
        :ok
      end)

      assert_receive {:telemetry, measurements, metadata}
      assert is_integer(measurements[:duration])
      # At least 10ms in native time (nanoseconds on most systems)
      assert measurements[:duration] >= 10_000_000
      assert metadata[:id] == 123
      refute Map.has_key?(metadata, :error)

      :telemetry.detach("test-measure-#{inspect(ref)}")
    end

    test "emits event with error flag when function raises" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-measure-error-#{inspect(ref)}",
        [:pristine, :test_measure_error],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      assert_raise RuntimeError, "test error", fn ->
        TelemetryAdapter.measure(:test_measure_error, %{op: "test"}, fn ->
          raise "test error"
        end)
      end

      assert_receive {:telemetry, measurements, metadata}
      assert is_integer(measurements[:duration])
      assert metadata[:error] == true
      assert metadata[:op] == "test"

      :telemetry.detach("test-measure-error-#{inspect(ref)}")
    end
  end

  describe "emit_counter/2" do
    test "emits counter event with count: 1" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-counter-#{inspect(ref)}",
        [:pristine, :test_counter],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:counter, measurements, metadata})
        end,
        nil
      )

      assert :ok = TelemetryAdapter.emit_counter(:test_counter, %{type: "request"})

      assert_receive {:counter, %{count: 1}, %{type: "request"}}

      :telemetry.detach("test-counter-#{inspect(ref)}")
    end
  end

  describe "emit_gauge/3" do
    test "emits gauge event with value" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-gauge-#{inspect(ref)}",
        [:pristine, :test_gauge],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:gauge, measurements, metadata})
        end,
        nil
      )

      assert :ok = TelemetryAdapter.emit_gauge(:test_gauge, 42.5, %{metric: "cpu"})

      assert_receive {:gauge, %{value: 42.5}, %{metric: "cpu"}}

      :telemetry.detach("test-gauge-#{inspect(ref)}")
    end

    test "handles integer values" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-gauge-int-#{inspect(ref)}",
        [:pristine, :test_gauge_int],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:gauge, measurements, metadata})
        end,
        nil
      )

      assert :ok = TelemetryAdapter.emit_gauge(:test_gauge_int, 100, %{metric: "count"})

      assert_receive {:gauge, %{value: 100}, %{metric: "count"}}

      :telemetry.detach("test-gauge-int-#{inspect(ref)}")
    end

    test "handles negative values" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-gauge-neg-#{inspect(ref)}",
        [:pristine, :test_gauge_neg],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:gauge, measurements, metadata})
        end,
        nil
      )

      assert :ok = TelemetryAdapter.emit_gauge(:test_gauge_neg, -10, %{metric: "temperature"})

      assert_receive {:gauge, %{value: -10}, %{metric: "temperature"}}

      :telemetry.detach("test-gauge-neg-#{inspect(ref)}")
    end
  end
end
