defmodule Tinkex.MetricsTest do
  use ExUnit.Case, async: false

  alias Tinkex.Metrics

  setup do
    # Stop any existing metrics server
    case Process.whereis(Metrics) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    # Start fresh metrics server for each test
    {:ok, pid} = Metrics.start_link(enabled: true)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, pid: pid}
  end

  describe "start_link/1" do
    test "starts the metrics server", %{pid: pid} do
      assert Process.alive?(pid)
    end
  end

  describe "increment/2" do
    test "increments counter by 1 by default" do
      :ok = Metrics.increment(:test_counter)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      assert snapshot.counters[:test_counter] == 1
    end

    test "increments counter by specified delta" do
      :ok = Metrics.increment(:test_counter, 5)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      assert snapshot.counters[:test_counter] == 5
    end

    test "accumulates multiple increments" do
      :ok = Metrics.increment(:test_counter, 3)
      :ok = Metrics.increment(:test_counter, 7)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      assert snapshot.counters[:test_counter] == 10
    end
  end

  describe "set_gauge/2" do
    test "sets gauge to specified value" do
      :ok = Metrics.set_gauge(:test_gauge, 42)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      assert snapshot.gauges[:test_gauge] == 42
    end

    test "overwrites previous gauge value" do
      :ok = Metrics.set_gauge(:test_gauge, 10)
      :ok = Metrics.set_gauge(:test_gauge, 20)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      assert snapshot.gauges[:test_gauge] == 20
    end
  end

  describe "record_histogram/2" do
    test "records histogram sample" do
      :ok = Metrics.record_histogram(:test_histogram, 100)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      hist = snapshot.histograms[:test_histogram]
      assert hist.count == 1
      assert hist.min == 100
      assert hist.max == 100
    end

    test "calculates statistics for multiple samples" do
      for value <- [10, 20, 30, 40, 50] do
        :ok = Metrics.record_histogram(:test_histogram, value)
      end

      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      hist = snapshot.histograms[:test_histogram]
      assert hist.count == 5
      assert hist.min == 10
      assert hist.max == 50
      assert hist.mean == 30.0
      assert hist.p50 == 30
    end

    test "calculates percentiles correctly" do
      # Record 100 samples: 1, 2, 3, ..., 100
      for value <- 1..100 do
        :ok = Metrics.record_histogram(:percentile_test, value)
      end

      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      hist = snapshot.histograms[:percentile_test]
      assert hist.count == 100
      # median of 50 and 51
      assert hist.p50 == 50.5
      assert hist.p95 == 95
      assert hist.p99 == 99
    end
  end

  describe "snapshot/0" do
    test "returns empty snapshot initially" do
      snapshot = Metrics.snapshot()

      assert snapshot.counters == %{}
      assert snapshot.gauges == %{}
      assert snapshot.histograms == %{}
    end

    test "returns all metrics types" do
      :ok = Metrics.increment(:counter1)
      :ok = Metrics.set_gauge(:gauge1, 100)
      :ok = Metrics.record_histogram(:hist1, 50)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()

      assert Map.has_key?(snapshot.counters, :counter1)
      assert Map.has_key?(snapshot.gauges, :gauge1)
      assert Map.has_key?(snapshot.histograms, :hist1)
    end
  end

  describe "reset/0" do
    test "clears all metrics" do
      :ok = Metrics.increment(:counter1, 100)
      :ok = Metrics.set_gauge(:gauge1, 50)
      :ok = Metrics.record_histogram(:hist1, 25)
      :ok = Metrics.flush()

      # Verify metrics were recorded
      snapshot_before = Metrics.snapshot()
      assert snapshot_before.counters[:counter1] == 100

      # Reset
      :ok = Metrics.reset()

      # Verify metrics are cleared
      snapshot_after = Metrics.snapshot()
      assert snapshot_after.counters == %{}
      assert snapshot_after.gauges == %{}
      assert snapshot_after.histograms == %{}
    end
  end

  describe "flush/0" do
    test "ensures all casts are processed" do
      :ok = Metrics.increment(:flush_test, 1)
      :ok = Metrics.increment(:flush_test, 1)
      :ok = Metrics.increment(:flush_test, 1)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      assert snapshot.counters[:flush_test] == 3
    end
  end

  describe "histogram statistics" do
    test "returns nil stats for empty histogram" do
      # Record and reset to create histogram structure but empty it
      :ok = Metrics.record_histogram(:empty_hist, 1)
      :ok = Metrics.reset()

      snapshot = Metrics.snapshot()
      # After reset, histogram should be gone entirely
      assert snapshot.histograms == %{}
    end

    test "handles single sample histogram" do
      :ok = Metrics.record_histogram(:single, 42)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      hist = snapshot.histograms[:single]
      assert hist.count == 1
      assert hist.mean == 42.0
      assert hist.min == 42
      assert hist.max == 42
      assert hist.p50 == 42
    end

    test "handles two sample histogram" do
      :ok = Metrics.record_histogram(:two, 10)
      :ok = Metrics.record_histogram(:two, 20)
      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      hist = snapshot.histograms[:two]
      assert hist.count == 2
      assert hist.mean == 15.0
      assert hist.min == 10
      assert hist.max == 20
      # average of 10 and 20
      assert hist.p50 == 15.0
    end
  end

  describe "telemetry integration" do
    test "handles HTTP stop events" do
      # Reset to clear any accumulated metrics from other tests
      :ok = Metrics.reset()

      # Simulate HTTP stop event
      :telemetry.execute(
        [:tinkex, :http, :request, :stop],
        %{duration: System.convert_time_unit(100, :millisecond, :native)},
        %{result: :ok}
      )

      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      assert snapshot.counters[:tinkex_requests_total] >= 1
      assert snapshot.counters[:tinkex_requests_success] >= 1
      assert Map.has_key?(snapshot.histograms, :tinkex_request_duration_ms)
    end

    test "tracks request failures" do
      # Reset to clear any accumulated metrics from other tests
      :ok = Metrics.reset()

      :telemetry.execute(
        [:tinkex, :http, :request, :stop],
        %{duration: System.convert_time_unit(50, :millisecond, :native)},
        %{result: :error}
      )

      :ok = Metrics.flush()

      snapshot = Metrics.snapshot()
      assert snapshot.counters[:tinkex_requests_total] >= 1
      assert snapshot.counters[:tinkex_requests_failure] >= 1
    end
  end
end
