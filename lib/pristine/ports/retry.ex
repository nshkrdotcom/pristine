defmodule Pristine.Ports.Retry do
  @moduledoc """
  Retry boundary for retrying operations.
  """

  @callback with_retry((-> term()), keyword()) :: term()
end
