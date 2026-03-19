defmodule Pristine.Adapters.Telemetry.Raw do
  @moduledoc """
  Telemetry adapter that emits raw event names without prefixes.
  """

  @behaviour Pristine.Ports.Telemetry

  @impl true
  def emit(event, metadata, measurements) do
    :telemetry.execute(event, measurements, metadata)
    :ok
  end

  @impl true
  def measure(event, metadata, fun) when is_function(fun, 0) do
    start = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start
    emit(event, metadata, %{duration: duration})
    result
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
