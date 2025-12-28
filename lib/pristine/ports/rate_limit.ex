defmodule Pristine.Ports.RateLimit do
  @moduledoc """
  Rate limit boundary.
  """

  @callback within_limit((-> term()), keyword()) :: term()
end
