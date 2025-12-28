defmodule Pristine.Adapters.Retry.Foundation do
  @moduledoc """
  Retry adapter backed by Foundation retry policies.

  This adapter provides:
  - Full retry orchestration via `with_retry/2`
  - HTTP-specific retry determination via `should_retry?/1`
  - Retry-After header parsing via `parse_retry_after/1`
  """

  @behaviour Pristine.Ports.Retry

  alias Foundation.Retry
  alias Foundation.Retry.HTTP

  @impl true
  def with_retry(fun, opts) when is_function(fun, 0) do
    policy = normalize_policy(opts)
    {result, _state} = Retry.run(fun, policy)
    result
  end

  @impl true
  @doc """
  Determine if an HTTP response should be retried.

  Delegates to `Foundation.Retry.HTTP.should_retry?/1`.

  ## Examples

      iex> Foundation.should_retry?(%{status: 429})
      true

      iex> Foundation.should_retry?(%{status: 400, headers: %{"x-should-retry" => "true"}})
      true
  """
  def should_retry?(response), do: HTTP.should_retry?(response)

  @impl true
  @doc """
  Parse retry delay from HTTP response headers.

  Delegates to `Foundation.Retry.HTTP.parse_retry_after/1`.

  ## Examples

      iex> Foundation.parse_retry_after(%{"retry-after" => "5"})
      5000
  """
  def parse_retry_after(headers), do: HTTP.parse_retry_after(headers)

  @doc """
  Create a retry policy with HTTP-aware retry-after support.

  This function creates a retry policy that will respect Retry-After headers
  from HTTP responses. Use this when you need the retry delays to be driven
  by server-specified delays.

  ## Options

  All standard `Foundation.Retry.Policy` options, plus:
  - `:response_headers_fun` - Function to extract headers from the result

  ## Examples

      policy = Foundation.http_aware_policy(
        max_attempts: 5,
        response_headers_fun: fn
          {:ok, %{headers: headers}} -> headers
          _ -> %{}
        end
      )
  """
  @spec http_aware_policy(keyword()) :: Retry.Policy.t()
  def http_aware_policy(opts \\ []) do
    headers_fun = Keyword.get(opts, :response_headers_fun, fn _ -> %{} end)
    base_opts = Keyword.delete(opts, :response_headers_fun)

    retry_after_ms_fun = fn result ->
      headers = headers_fun.(result)
      parse_retry_after(headers)
    end

    base_opts
    |> Keyword.put(:retry_after_ms_fun, retry_after_ms_fun)
    |> Retry.Policy.new()
  end

  defp normalize_policy(%Retry.Policy{} = policy), do: policy
  defp normalize_policy(opts) when is_list(opts), do: Retry.Policy.new(opts)
  defp normalize_policy(_), do: Retry.Policy.new()
end
