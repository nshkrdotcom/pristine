defmodule Tinkex.SessionManagerTest do
  use ExUnit.Case, async: false

  alias Tinkex.SessionManager

  # Mock Session API module
  defmodule MockSessionAPI do
    def create(%{type: "create_session"}, _opts) do
      {:ok, %{"session_id" => "session-#{System.unique_integer([:positive])}"}}
    end

    def heartbeat(%{session_id: _session_id}, _opts) do
      {:ok, %{}}
    end
  end

  defmodule FailingSessionAPI do
    def create(%{type: "create_session"}, _opts) do
      {:error, :connection_refused}
    end

    def heartbeat(%{session_id: _session_id}, _opts) do
      {:error, :connection_refused}
    end
  end

  setup do
    # Use a unique table name per test to avoid conflicts
    table_name = :"test_sessions_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      try do
        :ets.delete(table_name)
      rescue
        ArgumentError -> :ok
      end
    end)

    %{table_name: table_name}
  end

  describe "start_link/1" do
    test "starts the session manager", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "creates ETS table", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      assert :ets.whereis(table_name) != :undefined
      GenServer.stop(pid)
    end
  end

  describe "start_session/2" do
    test "creates a new session and returns session_id", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      config = %{timeout: 60_000, tags: ["test"]}
      {:ok, session_id} = SessionManager.start_session(config, name)

      assert is_binary(session_id)
      assert String.starts_with?(session_id, "session-")

      GenServer.stop(pid)
    end

    test "persists session to ETS", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      config = %{timeout: 60_000}
      {:ok, session_id} = SessionManager.start_session(config, name)

      # Verify it's in ETS
      [{^session_id, entry}] = :ets.lookup(table_name, session_id)
      assert entry.config == config
      assert entry.failure_count == 0
      assert is_nil(entry.last_error)

      GenServer.stop(pid)
    end

    test "returns error when session creation fails", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: FailingSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      config = %{timeout: 60_000}
      assert {:error, :connection_refused} = SessionManager.start_session(config, name)

      GenServer.stop(pid)
    end
  end

  describe "stop_session/2" do
    test "removes session from tracking", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      config = %{timeout: 60_000}
      {:ok, session_id} = SessionManager.start_session(config, name)

      # Verify it exists
      assert {:ok, _entry} = SessionManager.get_session(session_id, name)

      # Stop the session
      assert :ok = SessionManager.stop_session(session_id, name)

      # Verify it's removed
      assert :error = SessionManager.get_session(session_id, name)
      assert [] = :ets.lookup(table_name, session_id)

      GenServer.stop(pid)
    end

    test "handles non-existent session gracefully", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      assert :ok = SessionManager.stop_session("non-existent-session", name)

      GenServer.stop(pid)
    end
  end

  describe "list_sessions/1" do
    test "returns list of active session IDs", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      # Initially empty
      assert [] = SessionManager.list_sessions(name)

      # Create some sessions
      {:ok, session1} = SessionManager.start_session(%{timeout: 60_000}, name)
      {:ok, session2} = SessionManager.start_session(%{timeout: 60_000}, name)

      sessions = SessionManager.list_sessions(name)
      assert length(sessions) == 2
      assert session1 in sessions
      assert session2 in sessions

      GenServer.stop(pid)
    end
  end

  describe "get_session/2" do
    test "returns session entry for existing session", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      config = %{timeout: 60_000, tags: ["my-tag"]}
      {:ok, session_id} = SessionManager.start_session(config, name)

      {:ok, entry} = SessionManager.get_session(session_id, name)
      assert entry.config == config
      assert entry.failure_count == 0
      assert is_nil(entry.last_error)
      assert is_integer(entry.last_success_ms)

      GenServer.stop(pid)
    end

    test "returns :error for non-existent session", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      assert :error = SessionManager.get_session("non-existent", name)

      GenServer.stop(pid)
    end
  end

  describe "heartbeat handling" do
    test "successful heartbeat resets failure count", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 50
        )

      {:ok, session_id} = SessionManager.start_session(%{timeout: 60_000}, name)

      # Wait for a heartbeat cycle
      Process.sleep(100)

      {:ok, entry} = SessionManager.get_session(session_id, name)
      assert entry.failure_count == 0
      assert is_nil(entry.last_error)

      GenServer.stop(pid)
    end
  end

  describe "sessions_table/0" do
    test "returns default table name" do
      # Uses application env or default
      table = SessionManager.sessions_table()
      assert is_atom(table)
    end
  end

  describe "ETS persistence" do
    test "loads sessions from existing ETS table on startup", %{table_name: table_name} do
      # Pre-create the table and insert a session
      :ets.new(table_name, [:set, :public, :named_table])

      existing_entry = %{
        config: %{timeout: 60_000},
        last_success_ms: System.monotonic_time(:millisecond),
        last_error: nil,
        failure_count: 0
      }

      :ets.insert(table_name, {"existing-session", existing_entry})

      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: MockSessionAPI,
          heartbeat_interval_ms: 100_000
        )

      # Should have loaded the existing session
      sessions = SessionManager.list_sessions(name)
      assert "existing-session" in sessions

      GenServer.stop(pid)
    end
  end

  describe "failure limits" do
    test "removes session after max_failure_count", %{table_name: table_name} do
      name = :"test_manager_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: FailingSessionAPI,
          heartbeat_interval_ms: 10,
          max_failure_count: 2
        )

      # Manually create a session in the state (since create will fail)
      :ets.insert(
        table_name,
        {"failing-session",
         %{
           config: %{timeout: 60_000},
           last_success_ms: System.monotonic_time(:millisecond),
           last_error: nil,
           failure_count: 0
         }}
      )

      # Restart to pick up the ETS entry
      GenServer.stop(pid)

      {:ok, pid2} =
        SessionManager.start_link(
          name: name,
          sessions_table: table_name,
          session_api: FailingSessionAPI,
          heartbeat_interval_ms: 10,
          max_failure_count: 2
        )

      # Wait for heartbeats to exceed failure count
      Process.sleep(100)

      # Session should be removed after failures exceed max
      sessions = SessionManager.list_sessions(name)
      refute "failing-session" in sessions

      GenServer.stop(pid2)
    end
  end
end
