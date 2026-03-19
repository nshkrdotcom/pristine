defmodule Pristine.Ports.CircuitBreaker do
  @moduledoc """
  Circuit breaker boundary.
  """

  @callback call(String.t(), (-> term()), keyword()) :: term()
end
