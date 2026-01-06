defmodule Tinkex.Telemetry.Reporter do
  @moduledoc """
  Client-side telemetry reporter that batches events and ships them to the backend.

  A reporter is scoped to a single Tinker session. It:

    * Emits session start/end events.
    * Accepts generic events and exceptions via `log/4`, `log_exception/3`, and
      `log_fatal_exception/3`.
    * Batches events for efficient delivery.
    * Supports wait-until-drained semantics for graceful shutdown.

  ## Usage

      {:ok, reporter} = Reporter.start_link(
        session_id: "session-123",
        config: config,
        enabled: true
      )

      Reporter.log(reporter, "training.step", %{step: 1, loss: 0.5})
      Reporter.flush(reporter, sync?: true)
      Reporter.stop(reporter)
  """

  use GenServer
  require Logger

  alias Tinkex.Config

  @type severity :: :debug | :info | :warning | :error | :critical | String.t()

  @default_flush_interval_ms 10_000
  @default_flush_threshold 100
  @default_max_queue_size 10_000
  @default_max_batch_size 100

  @doc """
  Start a reporter for the provided session/config.

  ## Options

    * `:config` (**required**) - `Tinkex.Config.t()`
    * `:session_id` (**required**) - Tinker session id
    * `:attach_events?` - whether to attach telemetry handlers (default: true)
    * `:flush_interval_ms` - periodic flush interval (default: 10s)
    * `:flush_threshold` - flush when queue reaches this size (default: 100)
    * `:max_queue_size` - drop events beyond this size (default: 10_000)
    * `:max_batch_size` - events per batch (default: 100)
    * `:enabled` - override env flag; when false returns `:ignore`
    * `:name` - optional GenServer name
  """
  @spec start_link(keyword()) :: GenServer.on_start() | :ignore
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Log a generic telemetry event.

  Returns `true` if event was queued, `false` if reporter is nil or dead.
  """
  @spec log(pid() | nil, String.t(), map(), severity()) :: boolean()
  def log(pid, name, data \\ %{}, severity \\ :info)
  def log(nil, _name, _data, _severity), do: false

  def log(pid, name, data, severity) do
    safe_call(pid, {:log, name, data, severity})
  end

  @doc """
  Log an exception (non-fatal).

  Returns `true` if event was queued, `false` if reporter is nil or dead.
  """
  @spec log_exception(pid() | nil, Exception.t(), severity()) :: boolean()
  def log_exception(pid, exception, severity \\ :error)
  def log_exception(nil, _exception, _severity), do: false

  def log_exception(pid, exception, severity) do
    safe_call(pid, {:log_exception, exception, severity, :nonfatal})
  end

  @doc """
  Log a fatal exception and flush synchronously.

  Emits a session end event and flushes all pending events.
  Returns `true` if successful, `false` if reporter is nil or dead.
  """
  @spec log_fatal_exception(pid() | nil, Exception.t(), severity()) :: boolean()
  def log_fatal_exception(pid, exception, severity \\ :error)
  def log_fatal_exception(nil, _exception, _severity), do: false

  def log_fatal_exception(pid, exception, severity) do
    safe_call(pid, {:log_exception, exception, severity, :fatal})
  end

  @doc """
  Flush pending events.

  ## Options

    * `:sync?` - when true, blocks until all batches are sent (default: false)
    * `:wait_drained?` - when true with sync?, waits until queue is drained
  """
  @spec flush(pid() | nil, keyword()) :: :ok | boolean()
  def flush(pid, opts \\ [])
  def flush(nil, _opts), do: false

  def flush(pid, opts) do
    sync? = Keyword.get(opts, :sync?, false)
    wait_drained? = Keyword.get(opts, :wait_drained?, false)
    safe_call(pid, {:flush, sync?, wait_drained?})
  end

  @doc """
  Wait until all queued events have been flushed.

  Returns `true` if drained within timeout, `false` otherwise.
  """
  @spec wait_until_drained(pid() | nil, timeout()) :: boolean()
  def wait_until_drained(pid, timeout \\ 30_000)
  def wait_until_drained(nil, _timeout), do: false

  def wait_until_drained(pid, timeout) do
    safe_call(pid, {:wait_until_drained, timeout}, timeout + 1_000)
  end

  @doc """
  Stop the reporter gracefully.

  Emits a session end event and flushes all pending events before stopping.
  """
  @spec stop(pid() | nil, timeout()) :: :ok | boolean()
  def stop(pid, timeout \\ 5_000)
  def stop(nil, _timeout), do: false

  def stop(pid, timeout) do
    GenServer.stop(pid, :normal, timeout)
  catch
    :exit, _ -> false
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    enabled? = resolve_enabled?(opts)

    if enabled? do
      config = Keyword.fetch!(opts, :config)
      session_id = Keyword.fetch!(opts, :session_id)

      state = %{
        config: config,
        session_id: session_id,
        queue: :queue.new(),
        queue_size: 0,
        max_queue_size: Keyword.get(opts, :max_queue_size, @default_max_queue_size),
        max_batch_size: Keyword.get(opts, :max_batch_size, @default_max_batch_size),
        flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms),
        flush_threshold: Keyword.get(opts, :flush_threshold, @default_flush_threshold),
        attach_events?: Keyword.get(opts, :attach_events?, true),
        session_started: false,
        session_ended: false,
        push_counter: 0,
        flush_counter: 0,
        session_start_time: System.monotonic_time(:millisecond)
      }

      # Enqueue session start event
      state = enqueue_event(state, build_session_start_event(session_id))

      # Start periodic flush timer
      if state.flush_interval_ms > 0 do
        Process.send_after(self(), :flush_timer, state.flush_interval_ms)
      end

      {:ok, state}
    else
      :ignore
    end
  end

  @impl true
  def handle_call({:log, name, data, severity}, _from, state) do
    event = build_generic_event(state.session_id, name, data, severity)
    state = enqueue_event(state, event)
    state = maybe_flush_threshold(state)
    {:reply, true, state}
  end

  def handle_call({:log_exception, exception, severity, kind}, _from, state) do
    event = build_exception_event(state.session_id, exception, severity)
    state = enqueue_event(state, event)

    state =
      if kind == :fatal do
        # Enqueue session end for fatal exceptions
        state = enqueue_session_end(state)
        # Synchronous flush
        do_flush_sync(state)
      else
        maybe_flush_threshold(state)
      end

    {:reply, true, state}
  end

  def handle_call({:flush, sync?, wait_drained?}, _from, state) do
    state =
      if sync? do
        state = do_flush_sync(state)

        if wait_drained? do
          # Already flushed synchronously, so we're drained
          state
        else
          state
        end
      else
        do_flush_async(state)
      end

    {:reply, :ok, state}
  end

  def handle_call({:wait_until_drained, _timeout}, _from, state) do
    # For our simple implementation, check if queue is empty
    drained? = state.push_counter == state.flush_counter
    {:reply, drained?, state}
  end

  @impl true
  def handle_info(:flush_timer, state) do
    state = do_flush_async(state)

    if state.flush_interval_ms > 0 do
      Process.send_after(self(), :flush_timer, state.flush_interval_ms)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Enqueue session end if not already done
    state = enqueue_session_end(state)
    # Final synchronous flush
    _state = do_flush_sync(state)
    :ok
  end

  # Private helpers

  defp resolve_enabled?(opts) do
    case Keyword.get(opts, :enabled) do
      nil ->
        # Check config
        case Keyword.get(opts, :config) do
          %Config{telemetry_enabled?: false} -> false
          _ -> true
        end

      value ->
        value
    end
  end

  defp enqueue_event(state, event) do
    if state.queue_size >= state.max_queue_size do
      Logger.warning("Tinkex telemetry queue full, dropping event")
      state
    else
      %{
        state
        | queue: :queue.in(event, state.queue),
          queue_size: state.queue_size + 1,
          push_counter: state.push_counter + 1
      }
    end
  end

  defp maybe_flush_threshold(state) do
    if state.queue_size >= state.flush_threshold do
      do_flush_async(state)
    else
      state
    end
  end

  defp do_flush_async(state) do
    {events, remaining} = drain_batch(state.queue, state.max_batch_size)
    events_count = length(events)

    if events_count > 0 do
      # Fire and forget - in production would send to API
      send_events_async(state.config, state.session_id, events)

      %{
        state
        | queue: remaining,
          queue_size: state.queue_size - events_count,
          flush_counter: state.flush_counter + events_count
      }
    else
      state
    end
  end

  defp do_flush_sync(state) do
    {events, remaining} = drain_all(state.queue)
    events_count = length(events)

    if events_count > 0 do
      # Chunk into batches and send
      events
      |> Enum.chunk_every(state.max_batch_size)
      |> Enum.each(fn batch ->
        send_events_sync(state.config, state.session_id, batch)
      end)

      %{
        state
        | queue: remaining,
          queue_size: 0,
          flush_counter: state.flush_counter + events_count
      }
    else
      state
    end
  end

  defp drain_batch(queue, max_count) do
    drain_batch(queue, max_count, [])
  end

  defp drain_batch(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp drain_batch(queue, remaining, acc) do
    case :queue.out(queue) do
      {{:value, item}, queue} -> drain_batch(queue, remaining - 1, [item | acc])
      {:empty, queue} -> {Enum.reverse(acc), queue}
    end
  end

  defp drain_all(queue) do
    drain_all(queue, [])
  end

  defp drain_all(queue, acc) do
    case :queue.out(queue) do
      {{:value, item}, queue} -> drain_all(queue, [item | acc])
      {:empty, queue} -> {Enum.reverse(acc), queue}
    end
  end

  defp enqueue_session_end(state) do
    if state.session_ended do
      state
    else
      duration_ms = System.monotonic_time(:millisecond) - state.session_start_time
      event = build_session_end_event(state.session_id, duration_ms)
      state = enqueue_event(state, event)
      %{state | session_ended: true}
    end
  end

  # Event builders

  defp build_session_start_event(session_id) do
    %{
      event: "SESSION_START",
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_session_end_event(session_id, duration_ms) do
    %{
      event: "SESSION_END",
      session_id: session_id,
      duration_ms: duration_ms,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_generic_event(session_id, name, data, severity) do
    %{
      event: "GENERIC_EVENT",
      event_name: name,
      event_data: data,
      severity: to_string(severity),
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_exception_event(session_id, exception, severity) do
    %{
      event: "UNHANDLED_EXCEPTION",
      error_type: exception.__struct__ |> to_string() |> String.replace("Elixir.", ""),
      error_message: Exception.message(exception),
      severity: to_string(severity),
      traceback: Exception.format(:error, exception, []),
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # API calls (stubbed for now - would integrate with HTTP client)

  defp send_events_async(_config, _session_id, _events) do
    # In production: spawn async task to POST to /api/v1/telemetry
    # For now, just log
    :ok
  end

  defp send_events_sync(_config, _session_id, _events) do
    # In production: synchronous POST to /api/v1/telemetry
    # For now, just return ok
    :ok
  end

  defp safe_call(pid, message, timeout \\ 5_000) do
    GenServer.call(pid, message, timeout)
  catch
    :exit, _ -> false
  end
end
