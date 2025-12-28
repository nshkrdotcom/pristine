defmodule Pristine.Adapters.CircuitBreaker.Foundation do
  @moduledoc """
  Circuit breaker adapter backed by Foundation.CircuitBreaker.Registry.
  """

  @behaviour Pristine.Ports.CircuitBreaker

  alias Foundation.CircuitBreaker.Registry

  @impl true
  def call(name, fun, opts \\ []) when is_function(fun, 0) do
    registry = Keyword.get(opts, :registry, Registry.default_registry())
    Registry.call(registry, to_string(name), fun, opts)
  end
end
