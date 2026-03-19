defmodule Pristine.Adapters.AdmissionControl.Dispatch do
  @moduledoc """
  Admission-control adapter backed by `Foundation.Dispatch`.

  This adapter expects a started `Foundation.Dispatch` process via the
  `:dispatch` option. The handle may be a pid or any registered
  `GenServer.server()` reference accepted by `Foundation.Dispatch`.

  When admission control is explicitly enabled, invalid dispatch configuration
  raises instead of silently degrading to a noop.
  """

  @behaviour Pristine.Ports.AdmissionControl

  alias Foundation.Dispatch

  @impl true
  def with_admission(fun, opts) when is_function(fun, 0) do
    dispatch = dispatch_server!(opts)
    estimated_bytes = Keyword.get(opts, :estimated_bytes, 0)
    Dispatch.with_rate_limit(dispatch, estimated_bytes, fun)
  end

  @impl true
  def set_backoff(duration_ms, opts) when is_integer(duration_ms) and duration_ms >= 0 do
    dispatch = dispatch_server!(opts)
    Dispatch.set_backoff(dispatch, duration_ms)
  end

  defp dispatch_server!(opts) do
    case Keyword.fetch(opts, :dispatch) do
      {:ok, dispatch} ->
        validate_dispatch!(dispatch)

      :error ->
        raise ArgumentError,
              "dispatch option is required when admission control is enabled"
    end
  end

  defp validate_dispatch!(dispatch) do
    if dispatch_running?(dispatch) do
      dispatch
    else
      raise ArgumentError,
            "dispatch must be a running Foundation.Dispatch server handle, got: #{inspect(dispatch)}"
    end
  end

  defp dispatch_running?(dispatch) when is_pid(dispatch), do: Process.alive?(dispatch)

  defp dispatch_running?(dispatch) do
    case lookup_dispatch(dispatch) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _other -> false
    end
  end

  defp lookup_dispatch(dispatch) do
    GenServer.whereis(dispatch)
  rescue
    ArgumentError -> nil
  end
end
