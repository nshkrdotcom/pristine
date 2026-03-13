defmodule Pristine.Adapters.AdmissionControl.Noop do
  @moduledoc """
  Admission-control adapter that performs no coordination.
  """

  @behaviour Pristine.Ports.AdmissionControl

  @impl true
  def with_admission(fun, _opts) when is_function(fun, 0), do: fun.()

  @impl true
  def set_backoff(_duration_ms, _opts), do: :ok
end
