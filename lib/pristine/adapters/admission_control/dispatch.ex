defmodule Pristine.Adapters.AdmissionControl.Dispatch do
  @moduledoc """
  Admission-control adapter backed by `Foundation.Dispatch`.

  This adapter expects a started `Foundation.Dispatch` process via the
  `:dispatch` option. When no dispatch pid is configured it degrades to a noop.
  """

  @behaviour Pristine.Ports.AdmissionControl

  alias Foundation.Dispatch

  @impl true
  def with_admission(fun, opts) when is_function(fun, 0) do
    case Keyword.get(opts, :dispatch) do
      dispatch when is_pid(dispatch) ->
        estimated_bytes = Keyword.get(opts, :estimated_bytes, 0)
        Dispatch.with_rate_limit(dispatch, estimated_bytes, fun)

      _other ->
        fun.()
    end
  end

  @impl true
  def set_backoff(duration_ms, opts) when is_integer(duration_ms) and duration_ms >= 0 do
    case Keyword.get(opts, :dispatch) do
      dispatch when is_pid(dispatch) ->
        Dispatch.set_backoff(dispatch, duration_ms)

      _other ->
        :ok
    end
  end
end
