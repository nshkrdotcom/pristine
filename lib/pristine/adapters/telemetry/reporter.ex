defmodule Pristine.Adapters.Telemetry.Reporter do
  @moduledoc """
  Telemetry adapter backed by TelemetryReporter.
  """

  @behaviour Pristine.Ports.Telemetry

  @impl true
  def emit(event, meta, meas) do
    TelemetryReporter.log(TelemetryReporter, to_string(event), %{meta: meta, meas: meas})
  end
end
