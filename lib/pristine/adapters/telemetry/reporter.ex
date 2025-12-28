defmodule Pristine.Adapters.Telemetry.Reporter do
  @moduledoc """
  Telemetry adapter backed by TelemetryReporter.

  This adapter sends telemetry events to TelemetryReporter for external
  reporting and aggregation.
  """

  @behaviour Pristine.Ports.Telemetry

  @impl true
  def emit(event, meta, meas) do
    TelemetryReporter.log(TelemetryReporter, to_string(event), %{meta: meta, meas: meas})
    :ok
  end

  @impl true
  def measure(event, metadata, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time
      emit(event, metadata, %{duration: duration})
      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time
        emit(event, Map.put(metadata, :error, true), %{duration: duration})
        reraise e, __STACKTRACE__
    end
  end

  @impl true
  def emit_counter(event, metadata) do
    emit(event, metadata, %{count: 1})
  end

  @impl true
  def emit_gauge(event, value, metadata) do
    emit(event, metadata, %{value: value})
  end
end
