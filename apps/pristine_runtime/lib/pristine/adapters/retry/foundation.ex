defmodule Pristine.Adapters.Retry.Foundation do
  @moduledoc """
  Retry adapter backed by Foundation retry policies.

  This adapter provides:
  - Full retry orchestration via `with_retry/2`
  - Opt-in `:retry_budget_ms` stops before a delay would reach the total call
    budget and returns the last result, including time spent in the initial attempt.
  - HTTP-specific retry determination via `should_retry?/1`
  - Retry-After header parsing via `parse_retry_after/1`
  - Optional `Pristine.Cancellation` integration that interrupts the default
    retry wait and prevents later attempts once cancellation is terminal.

  When a caller supplies a custom `:sleep_fun`, Pristine preserves that hook.
  Cancellation is checked immediately before and after the custom sleeper; a
  sleeper that blocks internally must cooperate with the same cancellation token
  if it needs mid-sleep interruption.
  """

  @behaviour Pristine.Ports.Retry

  alias Foundation.{Backoff, Retry}
  alias Foundation.Retry.{Handler, HTTP, Runner}
  alias Pristine.{Cancellation, Error}

  @impl true
  def with_retry(fun, opts) when is_function(fun, 0) do
    {policy, opts} = normalize_policy_opts(opts)
    cancellation = normalize_cancellation!(Keyword.get(opts, :cancellation))
    cancellation_tag = make_ref()
    configured_sleep_fun = Keyword.get(opts, :sleep_fun)
    sleep_fun = cancellable_sleep_fun(configured_sleep_fun, cancellation, cancellation_tag)
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)

    before_attempt =
      opts
      |> Keyword.get(:before_attempt, fn _attempt -> :ok end)
      |> cancellable_before_attempt(cancellation, cancellation_tag)

    handler = Handler.new(handler_opts(policy))
    wrapped_fun = wrap_fun(fun, policy, cancellation, cancellation_tag)
    budget = Keyword.get(opts, :retry_budget_ms)
    budget_tag = make_ref()
    delay_fun = budgeted_delay_fun(policy, budget, time_fun, budget_tag)

    try do
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
    catch
      {^budget_tag, result} -> result
      {^cancellation_tag, %Error{type: :cancelled} = error} -> {:error, error}
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
  def parse_retry_after(response_or_headers, opts \\ [])

  def parse_retry_after(%{headers: headers}, opts), do: parse_retry_after(headers, opts)
  def parse_retry_after(%{"headers" => headers}, opts), do: parse_retry_after(headers, opts)

  def parse_retry_after(headers, opts) do
    case retry_after_header_present?(headers) do
      true -> HTTP.parse_retry_after(headers, 0)
      false -> reset_at_retry_after(headers, opts)
    end
  end

  @impl true
  def build_policy(opts \\ []) do
    Retry.Policy.new(opts)
  end

  @impl true
  def build_backoff(opts \\ []) do
    case {Keyword.get(opts, :base_ms), Keyword.get(opts, :max_ms)} do
      {0, _max} -> zero_backoff(opts)
      {_base, 0} -> zero_backoff(opts)
      _other -> Backoff.Policy.new(opts)
    end
  end

  defp zero_backoff(opts) do
    opts
    |> Keyword.put(:base_ms, 1)
    |> Keyword.put(:max_ms, 1)
    |> Backoff.Policy.new()
    |> Map.put(:base_ms, 0)
    |> Map.put(:max_ms, 0)
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
        policy_opts = Keyword.delete(remaining, :cancellation)
        {normalize_policy(policy_opts), remaining}

      {%Retry.Policy{} = policy, remaining} ->
        {policy, remaining}

      {policy_opts, remaining} when is_list(policy_opts) ->
        {Retry.Policy.new(policy_opts), remaining}

      {_other, remaining} ->
        {Retry.Policy.new(), remaining}
    end
  end

  defp normalize_policy_opts(opts), do: {normalize_policy(opts), []}

  defp wrap_fun(fun, %Retry.Policy{} = policy, cancellation, cancellation_tag) do
    fn ->
      throw_if_cancelled(cancellation, cancellation_tag)
      result = fun.()

      if policy.retry_on.(result) do
        {:error, {:retry, result}}
      else
        {:ok, {:result, result}}
      end
    end
  end

  defp cancellable_before_attempt(before_attempt, nil, _tag), do: before_attempt

  defp cancellable_before_attempt(before_attempt, %Cancellation{} = cancellation, tag) do
    fn attempt ->
      throw_if_cancelled(cancellation, tag)
      before_attempt.(attempt)
    end
  end

  defp cancellable_sleep_fun(nil, nil, _tag), do: &Process.sleep/1
  defp cancellable_sleep_fun(sleep_fun, nil, _tag) when is_function(sleep_fun, 1), do: sleep_fun

  defp cancellable_sleep_fun(nil, %Cancellation{} = cancellation, tag) do
    fn delay_ms ->
      case Cancellation.await(cancellation, delay_ms) do
        :cancelled -> throw({tag, Error.cancelled_error()})
        :timeout -> :ok
      end
    end
  end

  defp cancellable_sleep_fun(sleep_fun, %Cancellation{} = cancellation, tag)
       when is_function(sleep_fun, 1) do
    fn delay_ms ->
      throw_if_cancelled(cancellation, tag)
      result = sleep_fun.(delay_ms)
      throw_if_cancelled(cancellation, tag)
      result
    end
  end

  defp normalize_cancellation!(nil), do: nil
  defp normalize_cancellation!(%Cancellation{} = cancellation), do: cancellation

  defp normalize_cancellation!(_other) do
    raise ArgumentError, ":cancellation must be a Pristine.Cancellation token"
  end

  defp throw_if_cancelled(nil, _tag), do: :ok

  defp throw_if_cancelled(%Cancellation{} = cancellation, tag) do
    if Cancellation.cancelled?(cancellation) do
      throw({tag, Error.cancelled_error()})
    else
      :ok
    end
  end

  defp budgeted_delay_fun(policy, nil, _time_fun, _tag), do: delay_fun(policy)

  defp budgeted_delay_fun(policy, budget, time_fun, tag)
       when is_integer(budget) and budget >= 0 do
    started_at = time_fun.(:millisecond)
    delay = delay_fun(policy)

    fn result, handler ->
      milliseconds = delay.(result, handler)

      if time_fun.(:millisecond) - started_at + milliseconds >= budget do
        throw({tag, unwrap_retry_result(result)})
      end

      milliseconds
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

  defp reset_at_retry_after(headers, opts) do
    opts
    |> Keyword.get(:reset_at_headers, [])
    |> Enum.find_value(fn header ->
      case header_value(headers, header) do
        nil -> nil
        value -> reset_delta_ms(value)
      end
    end)
  end

  defp retry_after_header_present?(headers) do
    not is_nil(header_value(headers, "retry-after")) or
      not is_nil(header_value(headers, "retry-after-ms"))
  end

  defp header_value(headers, name) when is_map(headers) do
    downcased_name = String.downcase(name)

    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == downcased_name and is_binary(value), do: value
    end)
  end

  defp header_value(headers, name) when is_list(headers) do
    downcased_name = String.downcase(name)

    Enum.find_value(headers, fn
      {key, value} when is_binary(value) ->
        if String.downcase(to_string(key)) == downcased_name, do: value

      _other ->
        nil
    end)
  end

  defp header_value(_headers, _name), do: nil

  defp reset_delta_ms(value) when is_binary(value) do
    case Integer.parse(value) do
      {epoch, _rest} when epoch >= 0 ->
        now_epoch = DateTime.utc_now() |> DateTime.to_unix()
        max(epoch - now_epoch, 0) * 1_000

      _other ->
        nil
    end
  end

  defp reset_delta_ms(_value), do: nil
end
