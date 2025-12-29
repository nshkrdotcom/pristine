defmodule Pristine.Adapters.Future.Polling do
  @moduledoc """
  Future polling adapter with configurable backoff.

  Polls a server-side future until it completes, fails, or times out.
  Uses Foundation.Backoff for delay calculation between polls.

  ## Features

    * Configurable poll interval
    * Exponential, linear, or no backoff
    * Maximum poll time with timeout
    * State change callbacks
    * Telemetry integration

  ## Usage

      {:ok, task} = Polling.poll("req_123", context, [
        poll_interval_ms: 1000,
        max_poll_time_ms: 60_000,
        backoff: :exponential
      ])

      case Polling.await(task, 120_000) do
        {:ok, result} -> handle_result(result)
        {:error, :poll_timeout} -> handle_timeout()
        {:error, reason} -> handle_error(reason)
      end

  ## Response Handling

  The adapter expects poll responses to have a `type` field:

    * `"try_again"` - Continue polling
    * `"completed"` or `"success"` - Return the result
    * `"failed"` or `"error"` - Return an error

  ## Telemetry Events

    * `[:pristine, :future, :poll_start]` - Polling started
    * `[:pristine, :future, :poll_attempt]` - Each poll attempt
    * `[:pristine, :future, :poll_complete]` - Polling completed
    * `[:pristine, :future, :poll_error]` - Polling failed
  """

  @behaviour Pristine.Ports.Future

  alias Foundation.{Backoff, Poller}
  alias Pristine.Core.{Context, Headers, Request, Response, TelemetryHeaders}

  @default_poll_interval_ms 1_000
  @default_max_poll_time_ms 300_000

  defmodule State do
    @moduledoc false
    @enforce_keys [:request_id, :context, :start_time]
    defstruct [
      :request_id,
      :context,
      :retrieve_endpoint,
      :backoff_policy,
      :max_poll_time_ms,
      :on_state_change,
      :start_time,
      :sleep_fun,
      :cache_owner,
      :cache_enabled
    ]

    @type t :: %__MODULE__{
            request_id: String.t(),
            context: Context.t(),
            retrieve_endpoint: String.t(),
            backoff_policy: Backoff.Policy.t(),
            max_poll_time_ms: non_neg_integer() | :infinity,
            on_state_change: (map() -> :ok) | nil,
            start_time: integer(),
            sleep_fun: (non_neg_integer() -> any()),
            cache_owner: pid(),
            cache_enabled: boolean()
          }
  end

  defmodule Combined do
    @moduledoc false
    @enforce_keys [:futures, :transform, :timeout]
    defstruct [:futures, :transform, :timeout]

    @type t :: %__MODULE__{
            futures: [Task.t()],
            transform: (list() -> term()),
            timeout: non_neg_integer() | :infinity
          }
  end

  @impl true
  def poll(request_id, %Context{} = context, opts \\ []) do
    cache_owner = self()
    cache_enabled = Keyword.get(opts, :cache, true)

    case maybe_cached_result(cache_owner, request_id, cache_enabled) do
      {:ok, result} ->
        {:ok, Task.async(fn -> {:ok, result} end)}

      :miss ->
        state = build_state(request_id, context, opts, cache_owner, cache_enabled)

        emit_telemetry(:poll_start, %{request_id: request_id}, %{})

        task = Task.async(fn -> poll_loop(state) end)
        {:ok, task}
    end
  end

  @impl true
  def await(%Task{} = task, timeout) do
    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :await_timeout}

      {:exit, reason} ->
        {:error, {:task_exit, reason}}
    end
  end

  def await(%Combined{} = combined, timeout) do
    effective_timeout =
      case {combined.timeout, timeout} do
        {:infinity, other} -> other
        {value, :infinity} -> value
        {value, other} when is_integer(value) and is_integer(other) -> min(value, other)
        {value, _other} -> value
      end

    await_many(combined.futures, combined.transform, effective_timeout)
  end

  @impl true
  def combine(futures, transform, opts \\ [])
      when is_list(futures) and is_function(transform, 1) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    {:ok, %Combined{futures: futures, transform: transform, timeout: timeout}}
  end

  defp build_state(request_id, context, opts, cache_owner, cache_enabled) do
    interval = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)
    max_time = Keyword.get(opts, :max_poll_time_ms, @default_max_poll_time_ms)
    backoff_type = Keyword.get(opts, :backoff, :exponential)

    backoff_policy =
      Backoff.Policy.new(
        strategy: normalize_backoff_strategy(backoff_type),
        base_ms: interval,
        max_ms: interval * 10
      )

    %State{
      request_id: request_id,
      context: context,
      retrieve_endpoint: Keyword.get(opts, :retrieve_endpoint, "/api/v1/retrieve_future"),
      backoff_policy: backoff_policy,
      max_poll_time_ms: max_time,
      on_state_change: Keyword.get(opts, :on_state_change),
      start_time: System.monotonic_time(:millisecond),
      sleep_fun: Keyword.get(opts, :sleep_fun, &Process.sleep/1),
      cache_owner: cache_owner,
      cache_enabled: cache_enabled
    }
  end

  defp normalize_backoff_strategy(:none), do: :constant
  defp normalize_backoff_strategy(:linear), do: :linear
  defp normalize_backoff_strategy(:exponential), do: :exponential
  defp normalize_backoff_strategy(other), do: other

  defp poll_loop(%State{} = state) do
    attempt_key = {:poll_attempt, make_ref()}
    Process.put(attempt_key, 0)

    step_fun = fn attempt ->
      Process.put(attempt_key, attempt)
      emit_telemetry(:poll_attempt, %{request_id: state.request_id, attempt: attempt}, %{})

      retrieve_future(state, attempt)
      |> handle_poll_result(state, attempt)
    end

    case Poller.run(step_fun,
           backoff: state.backoff_policy,
           sleep_fun: state.sleep_fun,
           timeout_ms: state.max_poll_time_ms
         ) do
      {:ok, response} ->
        {:ok, response}

      {:error, :timeout} ->
        attempts = Process.get(attempt_key, 0)

        emit_telemetry(:poll_error, %{request_id: state.request_id, reason: :poll_timeout}, %{
          elapsed_ms: elapsed_time(state),
          attempts: attempts
        })

        {:error, :poll_timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_poll_result({:ok, %{"type" => "try_again"} = response}, state, _attempt) do
    notify_state_change(state, response)
    {:retry, :try_again}
  end

  defp handle_poll_result({:ok, %{"type" => type} = response}, state, attempt)
       when type in ["completed", "success"] do
    poll_complete(state, response, attempt)
  end

  defp handle_poll_result({:ok, %{"type" => type, "error" => error}}, state, attempt)
       when type in ["failed", "error"] do
    poll_failure(state, error, attempt, {:request_failed, error})
  end

  defp handle_poll_result({:ok, %{"status" => "complete"} = response}, state, attempt) do
    poll_complete(state, response, attempt)
  end

  defp handle_poll_result({:ok, %{"status" => "pending"}}, _state, _attempt) do
    {:retry, :pending}
  end

  defp handle_poll_result({:ok, response}, state, attempt) do
    if Map.has_key?(response, "result") do
      poll_complete(state, response, attempt)
    else
      {:retry, :pending}
    end
  end

  defp handle_poll_result({:error, {:http_error, 408, body, _headers}}, state, _attempt) do
    queue_state = extract_queue_state(body)
    notify_queue_state(state, queue_state, body)
    {:retry, :queue_state}
  end

  defp handle_poll_result({:error, {:http_error, 410, body, _headers}}, state, attempt) do
    poll_failure(state, :future_expired, attempt, {:future_expired, body})
  end

  defp handle_poll_result({:error, {:http_error, status, _body, _headers}}, _state, _attempt)
       when status >= 500 and status < 600 do
    {:retry, status}
  end

  defp handle_poll_result({:error, {:http_error, status, _body, _headers}}, _state, _attempt)
       when status in [429] do
    {:retry, status}
  end

  defp handle_poll_result({:error, {:http_error, status, body, _headers}}, state, attempt) do
    poll_failure(state, status, attempt, {:http_error, status, body})
  end

  defp handle_poll_result({:error, reason}, state, attempt) do
    handle_error(reason, state, attempt)
  end

  defp poll_complete(state, response, attempt) do
    emit_telemetry(:poll_complete, %{request_id: state.request_id}, %{
      elapsed_ms: elapsed_time(state),
      attempts: attempt
    })

    cache_success(state, response)
    {:ok, response}
  end

  defp poll_failure(state, reason, attempt, result) do
    emit_telemetry(:poll_error, %{request_id: state.request_id, reason: reason}, %{
      elapsed_ms: elapsed_time(state),
      attempts: attempt
    })

    {:error, result}
  end

  defp handle_error(reason, state, attempt) do
    if retriable?(reason) do
      {:retry, reason}
    else
      emit_telemetry(:poll_error, %{request_id: state.request_id, reason: reason}, %{
        elapsed_ms: elapsed_time(state),
        attempts: attempt
      })

      {:error, reason}
    end
  end

  defp retrieve_future(
         %State{request_id: id, context: context, retrieve_endpoint: endpoint} = state,
         attempt
       ) do
    transport = context.transport || raise ArgumentError, "transport is required"
    serializer = context.serializer || raise ArgumentError, "serializer is required"

    payload = %{"request_id" => id}

    with {:ok, body} <- serializer.encode(payload, []),
         {:ok, request} <- build_request(context, endpoint, body, attempt, state),
         {:ok, %Response{status: status, body: response_body, headers: headers}} <-
           transport.send(request, context) do
      decoded_result = serializer.decode(response_body, nil, [])

      case normalize_decode_result(decoded_result) do
        {:ok, decoded} ->
          if status >= 200 and status < 300 do
            {:ok, decoded}
          else
            {:error, {:http_error, status, decoded, headers}}
          end

        {:error, _reason} = error ->
          if status >= 200 and status < 300 do
            error
          else
            {:error, {:http_error, status, response_body, headers}}
          end
      end
    end
  end

  defp build_request(context, endpoint, body, attempt, state) do
    auth_modules = resolve_auth(context.auth)

    package_version =
      context.package_version ||
        case Application.spec(:pristine, :vsn) do
          nil -> nil
          vsn -> List.to_string(vsn)
        end

    telemetry_headers =
      TelemetryHeaders.platform_headers(package_version: package_version)
      |> Map.merge(TelemetryHeaders.retry_headers(attempt, state.max_poll_time_ms))
      |> Map.merge(context.headers)

    with {:ok, headers} <-
           Headers.build(telemetry_headers, %{}, auth_modules, %{}, "application/json") do
      {:ok,
       %Request{
         method: :post,
         url: build_url(context.base_url, endpoint),
         headers: headers,
         body: body
       }}
    end
  end

  defp build_url(nil, endpoint), do: endpoint
  defp build_url(base_url, endpoint), do: String.trim_trailing(base_url, "/") <> endpoint

  defp resolve_auth(auth) when is_list(auth), do: auth
  defp resolve_auth(auth) when is_map(auth), do: Map.get(auth, "default", [])
  defp resolve_auth(_auth), do: []

  defp normalize_decode_result({:ok, data}), do: {:ok, data}
  defp normalize_decode_result({:error, _} = error), do: error
  defp normalize_decode_result(data), do: {:ok, data}

  defp await_many(futures, transform, :infinity) do
    futures
    |> Enum.reduce_while({:ok, []}, fn future, {:ok, acc} ->
      case await(future, :infinity) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, transform.(Enum.reverse(values))}
      {:error, _} = error -> error
    end
  end

  defp await_many(futures, transform, timeout_ms)
       when is_integer(timeout_ms) and timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    futures
    |> Enum.reduce_while({:ok, []}, fn future, {:ok, acc} ->
      case await_with_deadline(future, deadline) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, transform.(Enum.reverse(values))}
      {:error, _} = error -> error
    end
  end

  defp await_with_deadline(future, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    if remaining == 0 do
      {:error, :await_timeout}
    else
      await(future, remaining)
    end
  end

  defp elapsed_time(%State{start_time: start}) do
    System.monotonic_time(:millisecond) - start
  end

  defp notify_state_change(%State{on_state_change: nil}, _response), do: :ok
  defp notify_state_change(%State{on_state_change: fun}, response), do: fun.(response)

  defp notify_queue_state(%State{on_state_change: nil}, _queue_state, _response), do: :ok

  defp notify_queue_state(%State{on_state_change: fun}, queue_state, response) do
    fun.(%{queue_state: queue_state, response: response})
  end

  defp extract_queue_state(%{} = body) do
    state =
      Map.get(body, "queue_state") ||
        Map.get(body, "queueState") ||
        Map.get(body, "state")

    normalize_queue_state(state)
  end

  defp extract_queue_state(_body), do: :unknown

  defp normalize_queue_state(nil), do: :unknown

  defp normalize_queue_state(state) when is_binary(state) do
    case String.upcase(state) do
      "ACTIVE" -> :active
      "PAUSED_RATE_LIMIT" -> :paused_rate_limit
      "PAUSED_CAPACITY" -> :paused_capacity
      _ -> :unknown
    end
  end

  defp normalize_queue_state(state) when is_atom(state), do: state
  defp normalize_queue_state(_state), do: :unknown

  defp retriable?({:http_error, status}) when status in [408, 429, 500, 502, 503, 504],
    do: true

  defp retriable?({:http_error, status, _body, _headers})
       when status in [408, 429, 500, 502, 503, 504],
       do: true

  defp retriable?(:timeout), do: true
  defp retriable?({:error, :timeout}), do: true
  defp retriable?({:error, :econnrefused}), do: true
  defp retriable?(_), do: false

  defp emit_telemetry(event, metadata, measurements) do
    :telemetry.execute([:pristine, :future, event], measurements, metadata)
  end

  defp cache_success(%State{cache_enabled: false}, _response), do: :ok

  defp cache_success(%State{cache_owner: owner, request_id: request_id}, response) do
    cache_result(owner, request_id, response)
  end

  defp maybe_cached_result(_owner, _request_id, false), do: :miss

  defp maybe_cached_result(owner, request_id, true) do
    case :persistent_term.get(cache_key(owner, request_id), :missing) do
      :missing -> :miss
      result -> {:ok, result}
    end
  end

  defp cache_result(owner, request_id, result) do
    :persistent_term.put(cache_key(owner, request_id), result)
  end

  defp cache_key(owner, request_id), do: {:pristine_future_cache, owner, request_id}
end
