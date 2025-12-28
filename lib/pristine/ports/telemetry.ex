defmodule Pristine.Ports.Telemetry do
  @moduledoc """
  Telemetry boundary for emitting events.
  """

  @callback emit(atom(), map(), map()) :: :ok
end
