defmodule Pristine.Adapters.Retry.Noop do
  @moduledoc """
  Retry adapter that performs no retries.

  This adapter executes the function exactly once without any retry logic.
  Useful for testing or when retry behavior is not desired.
  """

  @behaviour Pristine.Ports.Retry

  @impl true
  def with_retry(fun, _opts) when is_function(fun, 0) do
    fun.()
  end

  @impl true
  def should_retry?(_response), do: false

  @impl true
  def parse_retry_after(_headers), do: nil
end
