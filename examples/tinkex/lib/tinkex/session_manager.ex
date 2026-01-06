defmodule Tinkex.SessionManager do
  @moduledoc """
  Manages Tinkex sessions and heartbeats across multiple configs.

  The SessionManager is a GenServer that:
  - Creates new sessions via the Session API
  - Maintains heartbeat tracking for active sessions
  - Persists session state to ETS for crash recovery
  - Removes sessions after sustained heartbeat failures

  ## Options

  - `:name` - Process name (default: `Tinkex.SessionManager`)
  - `:sessions_table` - ETS table name (default: `:tinkex_sessions`)
  - `:heartbeat_interval_ms` - Time between heartbeats (default: `10_000`)
  - `:heartbeat_warning_after_ms` - Warn after this duration of failures (default: `120_000`)
  - `:max_failure_count` - Remove session after N consecutive failures (default: `:infinity`)
  - `:max_failure_duration_ms` - Remove session after this failure duration (default: `:infinity`)
  - `:session_api` - Module implementing session API (default: `Tinkex.API.Session`)
  """

  use GenServer
  require Logger

  alias Tinkex.PoolKey

  @type session_id :: String.t()
  @type config :: map()
  @type session_entry :: %{
          config: config(),
          last_success_ms: non_neg_integer(),
          last_error: term() | nil,
          failure_count: non_neg_integer()
        }

  @type state :: %{
          sessions: %{session_id() => session_entry()},
          sessions_table: atom(),
          heartbeat_interval_ms: non_neg_integer(),
          heartbeat_warning_after_ms: non_neg_integer(),
          max_failure_count: non_neg_integer() | :infinity,
          max_failure_duration_ms: non_neg_integer() | :infinity,
          session_api: module(),
          timer_ref: reference() | nil
        }

  @doc """
  Start the SessionManager process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Create a new session for the given config.

  Returns `{:ok, session_id}` on success or `{:error, reason}` on failure.
  """
  @spec start_session(config(), GenServer.server()) :: {:ok, session_id()} | {:error, term()}
  def start_session(config, server \\ __MODULE__) when is_map(config) do
    timeout =
      Map.get(config, :timeout, 60_000) + timeout_buffer(Map.get(config, :timeout, 60_000))

    GenServer.call(server, {:start_session, config}, timeout)
  end

  @doc """
  Stop tracking a session.

  This is a synchronous call to ensure the session is removed from heartbeat
  tracking before returning. This prevents race conditions where a heartbeat
  fires after the caller has shut down but before the session was removed.
  """
  @spec stop_session(session_id(), GenServer.server()) :: :ok
  def stop_session(session_id, server \\ __MODULE__) when is_binary(session_id) do
    GenServer.call(server, {:stop_session, session_id}, 5_000)
  catch
    :exit, _ -> :ok
  end

  @doc """
  Get the ETS table name for sessions.
  """
  @spec sessions_table() :: atom()
  def sessions_table do
    Application.get_env(:tinkex, :sessions_table, :tinkex_sessions)
  end

  @doc """
  Get all active session IDs.
  """
  @spec list_sessions(GenServer.server()) :: [session_id()]
  def list_sessions(server \\ __MODULE__) do
    GenServer.call(server, :list_sessions, 5_000)
  catch
    :exit, _ -> []
  end

  @doc """
  Get session info for a specific session.
  """
  @spec get_session(session_id(), GenServer.server()) :: {:ok, session_entry()} | :error
  def get_session(session_id, server \\ __MODULE__) when is_binary(session_id) do
    GenServer.call(server, {:get_session, session_id}, 5_000)
  catch
    :exit, _ -> :error
  end

  # Private helpers

  defp timeout_buffer(timeout_ms) when timeout_ms < 5_000, do: 5_000
  defp timeout_buffer(_timeout_ms), do: 1_000

  # GenServer callbacks

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :sessions_table, sessions_table())
    ensure_sessions_table(table)

    heartbeat_interval_ms = Keyword.get(opts, :heartbeat_interval_ms, 10_000)
    heartbeat_warning_after_ms = Keyword.get(opts, :heartbeat_warning_after_ms, 120_000)

    max_failure_count =
      opts
      |> Keyword.get(:max_failure_count)
      |> resolve_limit(Application.get_env(:tinkex, :max_failure_count, :infinity))

    max_failure_duration_ms =
      opts
      |> Keyword.get(:max_failure_duration_ms)
      |> resolve_limit(Application.get_env(:tinkex, :max_failure_duration_ms, :infinity))

    session_api = Keyword.get(opts, :session_api, Tinkex.API.Session)

    {:ok,
     %{
       sessions: load_sessions_from_ets(table),
       sessions_table: table,
       heartbeat_interval_ms: heartbeat_interval_ms,
       heartbeat_warning_after_ms: heartbeat_warning_after_ms,
       max_failure_count: max_failure_count,
       max_failure_duration_ms: max_failure_duration_ms,
       session_api: session_api,
       timer_ref: schedule_heartbeat(heartbeat_interval_ms)
     }}
  end

  @impl true
  def handle_call({:start_session, config}, _from, state) do
    case create_session(config, state.session_api) do
      {:ok, session_id} ->
        now_ms = now_ms()
        entry = %{config: config, last_success_ms: now_ms, last_error: nil, failure_count: 0}
        persist_session(state.sessions_table, session_id, entry)
        sessions = Map.put(state.sessions, session_id, entry)
        {:reply, {:ok, session_id}, %{state | sessions: sessions}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:stop_session, session_id}, _from, state) do
    safe_delete(state.sessions_table, session_id)
    {:reply, :ok, %{state | sessions: Map.delete(state.sessions, session_id)}}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    {:reply, Map.keys(state.sessions), state}
  end

  @impl true
  def handle_call({:get_session, session_id}, _from, state) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, entry} -> {:reply, {:ok, entry}, state}
      :error -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_info(:heartbeat, %{sessions: sessions} = state) do
    now_ms = now_ms()

    updated_sessions =
      Enum.reduce(sessions, %{}, fn {session_id, entry}, acc ->
        update_session_after_heartbeat(session_id, entry, acc, now_ms, state)
      end)

    timer_ref = schedule_heartbeat(state.heartbeat_interval_ms)
    {:noreply, %{state | sessions: updated_sessions, timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{timer_ref: ref}) do
    maybe_cancel_timer(ref)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # Session creation

  defp create_session(config, session_api) do
    request = %{
      tags: Map.get(config, :tags, ["tinkex-elixir"]),
      user_metadata: Map.get(config, :user_metadata),
      sdk_version: Tinkex.version(),
      type: "create_session"
    }

    case session_api.create(request, config: config) do
      {:ok, %{"session_id" => session_id}} when is_binary(session_id) ->
        {:ok, session_id}

      {:ok, %{session_id: session_id}} when is_binary(session_id) ->
        {:ok, session_id}

      {:ok, %{} = resp} ->
        case resp["session_id"] || Map.get(resp, :session_id) do
          session_id when is_binary(session_id) -> {:ok, session_id}
          _ -> {:error, :invalid_response}
        end

      {:error, _} = error ->
        error
    end
  end

  # Heartbeat handling

  defp update_session_after_heartbeat(session_id, entry, acc, now_ms, state) do
    case send_heartbeat(session_id, entry.config, state.session_api) do
      :ok ->
        handle_heartbeat_success(session_id, entry, acc, now_ms, state)

      {:error, last_error} ->
        handle_heartbeat_failure(session_id, entry, acc, now_ms, last_error, state)
    end
  end

  defp handle_heartbeat_success(session_id, entry, acc, now_ms, state) do
    updated_entry = %{entry | last_success_ms: now_ms, last_error: nil, failure_count: 0}
    persist_session(state.sessions_table, session_id, updated_entry)
    Map.put(acc, session_id, updated_entry)
  end

  defp handle_heartbeat_failure(session_id, entry, acc, now_ms, last_error, state) do
    maybe_warn(session_id, entry.last_success_ms, now_ms, last_error, state)
    updated_entry = %{entry | last_error: last_error}

    case maybe_remove_or_track_failure(
           state.sessions_table,
           session_id,
           updated_entry,
           now_ms,
           state
         ) do
      :remove ->
        acc

      tracked ->
        persist_session(state.sessions_table, session_id, tracked)
        Map.put(acc, session_id, tracked)
    end
  end

  defp send_heartbeat(session_id, config, session_api) do
    case maybe_heartbeat(session_id, config, session_api) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.debug("Heartbeat failed for #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_heartbeat(session_id, config, session_api) do
    pool = Map.get(config, :http_pool)
    base_url = Map.get(config, :base_url)

    resolved_pool =
      if pool && base_url do
        PoolKey.resolve_pool_name(pool, base_url, :session)
      else
        nil
      end

    if resolved_pool && Process.whereis(resolved_pool) == nil do
      Logger.warning(
        "Skipping heartbeat for #{session_id}: http_pool #{inspect(resolved_pool)} is not running"
      )

      {:error, :http_pool_not_alive}
    else
      safe_heartbeat(session_id, config, session_api)
    end
  end

  defp safe_heartbeat(session_id, config, session_api) do
    session_api.heartbeat(%{session_id: session_id}, config: config)
  rescue
    exception ->
      {:error, {:request_failed, Exception.message(exception)}}
  catch
    :exit, reason ->
      {:error, {:request_failed, "Heartbeat exited: #{inspect(reason)}"}}
  end

  # Failure handling

  defp maybe_remove_or_track_failure(table, session_id, entry, now_ms, state) do
    failure_count = entry.failure_count + 1
    time_since_success = now_ms - entry.last_success_ms

    cond do
      exceeds_count?(failure_count, state.max_failure_count) ->
        Logger.warning(
          "Removing session #{session_id} after #{failure_count} consecutive heartbeat failures"
        )

        safe_delete(table, session_id)
        :remove

      exceeds_duration?(time_since_success, state.max_failure_duration_ms) ->
        Logger.warning(
          "Removing session #{session_id} after #{time_since_success}ms without a successful heartbeat"
        )

        safe_delete(table, session_id)
        :remove

      true ->
        %{entry | failure_count: failure_count}
    end
  end

  defp exceeds_count?(_count, :infinity), do: false
  defp exceeds_count?(count, max) when is_integer(max), do: count > max

  defp exceeds_duration?(_duration, :infinity), do: false
  defp exceeds_duration?(duration, max) when is_integer(max), do: duration > max

  defp maybe_warn(session_id, last_success_ms, now_ms, last_error, state) do
    if now_ms - last_success_ms >= state.heartbeat_warning_after_ms do
      Logger.warning(
        "Heartbeat has failed for #{now_ms - last_success_ms}ms for session #{session_id}. " <>
          "Last error: #{inspect(last_error)}"
      )
    end
  end

  # Timer helpers

  defp schedule_heartbeat(interval_ms), do: Process.send_after(self(), :heartbeat, interval_ms)

  defp maybe_cancel_timer(ref) when is_reference(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  defp maybe_cancel_timer(_), do: :ok

  # ETS helpers

  defp ensure_sessions_table(table) do
    :ets.new(table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
  rescue
    ArgumentError -> table
  end

  defp load_sessions_from_ets(table) do
    case :ets.whereis(table) do
      :undefined ->
        %{}

      _ ->
        :ets.foldl(
          fn {session_id, entry}, acc ->
            Map.put(acc, session_id, normalize_entry(entry))
          end,
          %{},
          table
        )
    end
  rescue
    ArgumentError -> %{}
  end

  defp persist_session(table, session_id, entry) do
    :ets.insert(table, {session_id, entry})
  rescue
    ArgumentError -> :ok
  end

  defp safe_delete(table, key) do
    :ets.delete(table, key)
  rescue
    ArgumentError -> :ok
  end

  defp normalize_entry(%{failure_count: _} = entry), do: entry
  defp normalize_entry(entry), do: Map.put(entry, :failure_count, 0)

  defp resolve_limit(nil, default), do: default
  defp resolve_limit(:infinity, _default), do: :infinity
  defp resolve_limit(value, _default), do: value

  defp now_ms, do: System.monotonic_time(:millisecond)
end
