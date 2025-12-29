defmodule Pristine.Adapters.CircuitBreaker.Noop do
  @moduledoc """
  Circuit breaker adapter that performs no checks.
  """

  @behaviour Pristine.Ports.CircuitBreaker

  @impl true
  def call(_name, fun, _opts \\ []) when is_function(fun, 0) do
    fun.()
  end
end
