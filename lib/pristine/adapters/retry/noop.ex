defmodule Pristine.Adapters.Retry.Noop do
  @moduledoc """
  Retry adapter that performs no retries.
  """

  @behaviour Pristine.Ports.Retry

  @impl true
  def with_retry(fun, _opts) when is_function(fun, 0) do
    fun.()
  end
end
