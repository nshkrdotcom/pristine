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

  alias Foundation.Backoff
  alias Pristine.Core.{Context, Request, Response}

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
      :sleep_fun
    ]

    @type t :: %__MODULE__{
            request_id: String.t(),
            context: Context.t(),
            retrieve_endpoint: String.t(),
            backoff_policy: Backoff.Policy.t(),
            max_poll_time_ms: non_neg_integer() | :infinity,
            on_state_change: (map() -> :ok) | nil,
            start_time: integer(),
            sleep_fun: (non_neg_integer() -> any())
          }
  end

  @impl true
  def poll(request_id, %Context{} = context, opts \\ []) do
    state = build_state(request_id, context, opts)

    emit_telemetry(:poll_start, %{request_id: request_id}, %{})

    task = Task.async(fn -> poll_loop(state, 0) end)
    {:ok, task}
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

  defp build_state(request_id, context, opts) do
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
      sleep_fun: Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    }
  end

  defp normalize_backoff_strategy(:none), do: :constant
  defp normalize_backoff_strategy(:linear), do: :linear
  defp normalize_backoff_strategy(:exponential), do: :exponential
  defp normalize_backoff_strategy(other), do: other

  defp poll_loop(%State{} = state, attempt) do
    if timed_out?(state) do
      emit_telemetry(:poll_error, %{request_id: state.request_id, reason: :poll_timeout}, %{
        elapsed_ms: elapsed_time(state),
        attempts: attempt
      })

      {:error, :poll_timeout}
    else
      do_poll(state, attempt)
    end
  end

  defp do_poll(state, attempt) do
    emit_telemetry(:poll_attempt, %{request_id: state.request_id, attempt: attempt}, %{})

    case retrieve_future(state) do
      {:ok, %{"type" => "try_again"} = response} ->
        notify_state_change(state, response)
        delay = calculate_delay(state.backoff_policy, attempt)
        state.sleep_fun.(delay)
        poll_loop(state, attempt + 1)

      {:ok, %{"type" => type} = response} when type in ["completed", "success"] ->
        emit_telemetry(:poll_complete, %{request_id: state.request_id}, %{
          elapsed_ms: elapsed_time(state),
          attempts: attempt
        })

        {:ok, response}

      {:ok, %{"type" => type, "error" => error}} when type in ["failed", "error"] ->
        emit_telemetry(:poll_error, %{request_id: state.request_id, reason: error}, %{
          elapsed_ms: elapsed_time(state),
          attempts: attempt
        })

        {:error, {:request_failed, error}}

      {:ok, %{"status" => "complete"} = response} ->
        emit_telemetry(:poll_complete, %{request_id: state.request_id}, %{
          elapsed_ms: elapsed_time(state),
          attempts: attempt
        })

        {:ok, response}

      {:ok, %{"status" => "pending"}} ->
        delay = calculate_delay(state.backoff_policy, attempt)
        state.sleep_fun.(delay)
        poll_loop(state, attempt + 1)

      {:ok, response} ->
        # Unknown response format - check if it looks like a final result
        if Map.has_key?(response, "result") do
          emit_telemetry(:poll_complete, %{request_id: state.request_id}, %{
            elapsed_ms: elapsed_time(state),
            attempts: attempt
          })

          {:ok, response}
        else
          # Treat unknown response as try again
          delay = calculate_delay(state.backoff_policy, attempt)
          state.sleep_fun.(delay)
          poll_loop(state, attempt + 1)
        end

      {:error, reason} ->
        handle_error(reason, state, attempt)
    end
  end

  defp handle_error(reason, state, attempt) do
    if retriable?(reason) do
      delay = calculate_delay(state.backoff_policy, attempt)
      state.sleep_fun.(delay)
      poll_loop(state, attempt + 1)
    else
      emit_telemetry(:poll_error, %{request_id: state.request_id, reason: reason}, %{
        elapsed_ms: elapsed_time(state),
        attempts: attempt
      })

      {:error, reason}
    end
  end

  defp retrieve_future(%State{request_id: id, context: context, retrieve_endpoint: endpoint}) do
    transport = context.transport || raise ArgumentError, "transport is required"
    serializer = context.serializer || raise ArgumentError, "serializer is required"

    payload = %{"request_id" => id}

    with {:ok, body} <- serializer.encode(payload, []),
         request <- build_request(context, endpoint, body),
         {:ok, %Response{status: status, body: response_body}} <-
           transport.send(request, context),
         :ok <- check_status(status),
         result <- serializer.decode(response_body, nil, []) do
      normalize_decode_result(result)
    end
  end

  defp build_request(context, endpoint, body) do
    %Request{
      method: :post,
      url: build_url(context.base_url, endpoint),
      headers: Map.merge(context.headers, %{"content-type" => "application/json"}),
      body: body
    }
  end

  defp build_url(nil, endpoint), do: endpoint
  defp build_url(base_url, endpoint), do: String.trim_trailing(base_url, "/") <> endpoint

  defp check_status(status) when status >= 200 and status < 300, do: :ok
  defp check_status(status), do: {:error, {:http_error, status}}

  defp normalize_decode_result({:ok, data}), do: {:ok, data}
  defp normalize_decode_result({:error, _} = error), do: error
  defp normalize_decode_result(data), do: {:ok, data}

  defp timed_out?(%State{max_poll_time_ms: :infinity}), do: false

  defp timed_out?(%State{start_time: start, max_poll_time_ms: max}) do
    System.monotonic_time(:millisecond) - start > max
  end

  defp elapsed_time(%State{start_time: start}) do
    System.monotonic_time(:millisecond) - start
  end

  defp calculate_delay(policy, attempt) do
    Backoff.delay(policy, attempt)
  end

  defp notify_state_change(%State{on_state_change: nil}, _response), do: :ok
  defp notify_state_change(%State{on_state_change: fun}, response), do: fun.(response)

  defp retriable?({:http_error, status}) when status in [408, 429, 500, 502, 503, 504],
    do: true

  defp retriable?(:timeout), do: true
  defp retriable?({:error, :timeout}), do: true
  defp retriable?({:error, :econnrefused}), do: true
  defp retriable?(_), do: false

  defp emit_telemetry(event, metadata, measurements) do
    :telemetry.execute([:pristine, :future, event], measurements, metadata)
  end
end
