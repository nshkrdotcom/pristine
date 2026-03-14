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
  @compile {:no_warn_undefined, [TelemetryReporter]}

  @impl true
  def emit(event, meta, meas) do
    reporter = reporter_module()

    if Code.ensure_loaded?(reporter) and function_exported?(reporter, :log, 3) do
      reporter.log(reporter, format_event(event), %{meta: meta, meas: meas})
    else
      raise RuntimeError,
            "telemetry_reporter dependency is not available; add {:telemetry_reporter, \"~> 0.1.0\"} to use Pristine.Adapters.Telemetry.Reporter"
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

  defp reporter_module do
    Application.get_env(:pristine, :telemetry_reporter_module, TelemetryReporter)
  end

  defp format_event(event) when is_atom(event), do: Atom.to_string(event)
  defp format_event(event) when is_list(event), do: Enum.map_join(event, ".", &Atom.to_string/1)
end
