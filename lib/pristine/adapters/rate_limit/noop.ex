defmodule Pristine.Adapters.RateLimit.Noop do
  @moduledoc """
  Rate limit adapter that performs no limiting.
  """

  @behaviour Pristine.Ports.RateLimit

  @impl true
  def within_limit(fun, _opts) when is_function(fun, 0) do
    fun.()
  end
end
