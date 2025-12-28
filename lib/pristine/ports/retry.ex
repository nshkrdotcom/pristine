defmodule Pristine.Ports.Retry do
  @moduledoc """
  Retry boundary for retrying operations.

  Required callback:
  - `with_retry/2` - Execute a function with retry semantics

  Optional callbacks for HTTP-specific features:
  - `should_retry?/1` - Determine if a response should be retried
  - `parse_retry_after/1` - Extract retry delay from response headers
  """

  @callback with_retry((-> term()), keyword()) :: term()

  @doc """
  Determine if an HTTP response should be retried based on status code and headers.
  """
  @callback should_retry?(map()) :: boolean()

  @doc """
  Parse retry delay from HTTP response headers.
  Returns delay in milliseconds, or nil if not available.
  """
  @callback parse_retry_after(map()) :: non_neg_integer() | nil

  @optional_callbacks [should_retry?: 1, parse_retry_after: 1]
end
