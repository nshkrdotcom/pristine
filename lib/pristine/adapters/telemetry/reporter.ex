defmodule Pristine.Adapters.Telemetry.Reporter do
  @moduledoc """
  Compatibility telemetry adapter backed by TelemetryReporter.

  This adapter sends events directly to a reporter instance. Prefer
  `Pristine.Adapters.Telemetry.Foundation` plus
  `Pristine.Profiles.Foundation.attach_reporter/2` for new code so the runtime
  continues to emit standard `:telemetry` events and reporter export stays a
  handler concern.
  """

  @behaviour Pristine.Ports.Telemetry
  alias Pristine.TelemetryReporterSupport

  @impl true
  def emit(event, meta, meas) do
    case TelemetryReporterSupport.fetch() do
      {:ok, reporter} ->
        if function_exported?(reporter, :log, 3) do
          reporter.log(reporter, format_event(event), %{meta: meta, meas: meas})
        else
          TelemetryReporterSupport.raise_missing!()
        end

      {:error, :missing_dependency} ->
        TelemetryReporterSupport.raise_missing!()
    end

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

  defp format_event(event) when is_atom(event), do: Atom.to_string(event)
  defp format_event(event) when is_list(event), do: Enum.map_join(event, ".", &Atom.to_string/1)
end
