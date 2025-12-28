defmodule Pristine.Adapters.Telemetry.Noop do
  @moduledoc """
  Telemetry adapter that does nothing.

  Useful for testing or when telemetry is not desired.
  All operations are no-ops that return appropriate values
  without emitting any events.
  """

  @behaviour Pristine.Ports.Telemetry

  @impl true
  def emit(_event, _meta, _meas), do: :ok

  @impl true
  def measure(_event, _metadata, fun) when is_function(fun, 0), do: fun.()

  @impl true
  def emit_counter(_event, _metadata), do: :ok

  @impl true
  def emit_gauge(_event, _value, _metadata), do: :ok
end
