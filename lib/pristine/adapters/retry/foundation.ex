defmodule Pristine.Adapters.Retry.Foundation do
  @moduledoc """
  Retry adapter backed by Foundation retry policies.

  This adapter provides:
  - Full retry orchestration via `with_retry/2`
  - HTTP-specific retry determination via `should_retry?/1`
  - Retry-After header parsing via `parse_retry_after/1`
  """

  @behaviour Pristine.Ports.Retry

  alias Foundation.{Backoff, Retry}
  alias Foundation.Retry.{Handler, HTTP, Runner}

  @impl true
  def with_retry(fun, opts) when is_function(fun, 0) do
    {policy, opts} = normalize_policy_opts(opts)
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    before_attempt = Keyword.get(opts, :before_attempt, fn _attempt -> :ok end)

    handler = Handler.new(handler_opts(policy))
    wrapped_fun = wrap_fun(fun, policy)
    delay_fun = delay_fun(policy)

    case Runner.run(wrapped_fun,
           handler: handler,
           sleep_fun: sleep_fun,
           before_attempt: before_attempt,
           delay_fun: delay_fun,
           max_elapsed_ms: policy.max_elapsed_ms,
           time_fun: time_fun,
           rescue_exceptions: false
         ) do
      {:ok, {:result, result}} -> result
      {:error, {:retry, result}} -> result
      {:error, reason} -> {:error, reason}
      {:ok, other} -> other
    end
  end

  @impl true
  @doc """
  Determine if an HTTP response should be retried.

  Delegates to `Foundation.Retry.HTTP.should_retry?/1`.

  ## Examples

      iex> Pristine.Adapters.Retry.Foundation.should_retry?(%{status: 429})
      true

      iex> Pristine.Adapters.Retry.Foundation.should_retry?(%{
      ...>   status: 400,
      ...>   headers: %{"x-should-retry" => "true"}
      ...> })
      true
  """
  def should_retry?(response), do: HTTP.should_retry?(response)

  @impl true
  @doc """
  Parse retry delay from HTTP response headers.

  Delegates to `Foundation.Retry.HTTP.parse_retry_after/1`.

  ## Examples

      iex> Pristine.Adapters.Retry.Foundation.parse_retry_after(%{"retry-after" => "5"})
      5000
  """
  def parse_retry_after(%{headers: headers}), do: HTTP.parse_retry_after(headers)
  def parse_retry_after(%{"headers" => headers}), do: HTTP.parse_retry_after(headers)
  def parse_retry_after(headers), do: HTTP.parse_retry_after(headers)

  @impl true
  def build_policy(opts \\ []) do
    Retry.Policy.new(opts)
  end

  @impl true
  def build_backoff(opts \\ []) do
    Backoff.Policy.new(opts)
  end

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

  defp normalize_policy_opts(opts) when is_list(opts) do
    case Keyword.pop(opts, :policy) do
      {nil, remaining} ->
        {normalize_policy(remaining), remaining}

      {%Retry.Policy{} = policy, remaining} ->
        {policy, remaining}

      {policy_opts, remaining} when is_list(policy_opts) ->
        {Retry.Policy.new(policy_opts), remaining}

      {_other, remaining} ->
        {Retry.Policy.new(), remaining}
    end
  end

  defp normalize_policy_opts(opts), do: {normalize_policy(opts), []}

  defp wrap_fun(fun, %Retry.Policy{} = policy) do
    fn ->
      result = fun.()

      if policy.retry_on.(result) do
        {:error, {:retry, result}}
      else
        {:ok, {:result, result}}
      end
    end
  end

  defp delay_fun(%Retry.Policy{} = policy) do
    fn result, handler ->
      original = unwrap_retry_result(result)

      delay =
        case policy.retry_after_ms_fun do
          fun when is_function(fun, 1) -> fun.(original)
          _ -> nil
        end

      case delay do
        ms when is_integer(ms) and ms >= 0 -> ms
        _ -> Backoff.delay(policy.backoff, handler.attempt)
      end
    end
  end

  defp unwrap_retry_result({:error, {:retry, original}}), do: original
  defp unwrap_retry_result(original), do: original

  defp handler_opts(%Retry.Policy{} = policy) do
    opts = [max_retries: policy.max_attempts]

    if is_nil(policy.progress_timeout_ms) do
      Keyword.put(opts, :progress_timeout_ms, :infinity)
    else
      Keyword.put(opts, :progress_timeout_ms, policy.progress_timeout_ms)
    end
  end
end
