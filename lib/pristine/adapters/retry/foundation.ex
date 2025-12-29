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
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    before_attempt = Keyword.get(opts, :before_attempt, fn _attempt -> :ok end)

    state = Keyword.get(opts, :state, Retry.State.new(time_fun: time_fun))

    do_run(fun, policy, state, sleep_fun, time_fun, before_attempt)
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

  defp do_run(fun, policy, state, sleep_fun, time_fun, before_attempt) do
    case Retry.check_timeouts(state, policy, time_fun: time_fun) do
      {:error, reason} ->
        {:error, reason}

      :ok ->
        before_attempt.(state.attempt)
        result = fun.()

        case Retry.step(state, policy, result, time_fun: time_fun) do
          {:retry, delay_ms, next_state} ->
            sleep_fun.(delay_ms)
            do_run(fun, policy, next_state, sleep_fun, time_fun, before_attempt)

          {:halt, final_result, _final_state} ->
            final_result
        end
    end
  end
end
