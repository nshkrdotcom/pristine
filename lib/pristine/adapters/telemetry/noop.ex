defmodule Pristine.Adapters.Telemetry.Noop do
  @moduledoc """
  Telemetry adapter that does nothing.
  """

  @behaviour Pristine.Ports.Telemetry

  @impl true
  def emit(_event, _meta, _meas), do: :ok
end
