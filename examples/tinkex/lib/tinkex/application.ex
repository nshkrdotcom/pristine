defmodule Tinkex.Application do
  @moduledoc """
  OTP application for the Tinkex SDK.

  Initializes ETS tables for shared runtime state and supervises client-facing
  processes. This module provides the core supervision tree for Tinkex.

  ## Pool Configuration (Python Parity)

  Python SDK uses `httpx.Limits(max_connections=1000, max_keepalive_connections=20)`.
  Tinkex configures connection pools to approximate these limits:

  - `pool_size` - connections per pool (default: 50, env: `TINKEX_POOL_SIZE`)
  - `pool_count` - number of pools (default: 20, env: `TINKEX_POOL_COUNT`)
  - Total connections = pool_size * pool_count = 1000 (matching Python's max_connections)

  Override via application config or environment variables:

      # config.exs
      config :tinkex,
        pool_size: 100,
        pool_count: 10

      # Environment variables
      export TINKEX_POOL_SIZE=100
      export TINKEX_POOL_COUNT=10

  ## Supervised Processes

  The application starts the following supervised processes:

  - `Tinkex.Metrics` - Telemetry event aggregation
  - `Tinkex.Semaphore` - Concurrency limiting semaphore
  - `Tinkex.SamplingRegistry` - SamplingClient process registry with cleanup
  - `Task.Supervisor` - Async task execution
  - `Tinkex.SessionManager` - Session lifecycle and heartbeat management
  - `DynamicSupervisor` - Dynamic client process management
  """

  use Application

  alias Tinkex.Env
  alias Tinkex.Logging

  # Python SDK parity: max_connections=1000, max_keepalive_connections=20
  # size=50, count=20 gives 50*20=1000 total connections per destination
  @default_pool_size 50
  @default_pool_count 20

  @impl true
  def start(_type, _args) do
    ensure_ets_tables()

    env = Env.snapshot()
    apply_log_level(env)

    heartbeat_interval_ms = Application.get_env(:tinkex, :heartbeat_interval_ms, 10_000)

    heartbeat_warning_after_ms =
      Application.get_env(:tinkex, :heartbeat_warning_after_ms, 120_000)

    children = base_children(heartbeat_interval_ms, heartbeat_warning_after_ms)

    Supervisor.start_link(children, strategy: :one_for_one, name: Tinkex.Supervisor)
  end

  defp ensure_ets_tables do
    create_table(:tinkex_sampling_clients, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    create_table(:tinkex_rate_limiters, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    create_table(:tinkex_tokenizers, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    create_table(Tinkex.SessionManager.sessions_table(), [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  defp create_table(name, options) do
    :ets.new(name, options)
  rescue
    ArgumentError -> name
  end

  defp base_children(heartbeat_interval_ms, heartbeat_warning_after_ms) do
    [
      Tinkex.Metrics,
      Tinkex.Semaphore,
      Tinkex.SamplingRegistry,
      {Task.Supervisor, name: Tinkex.TaskSupervisor},
      {Tinkex.SessionManager,
       heartbeat_interval_ms: heartbeat_interval_ms,
       heartbeat_warning_after_ms: heartbeat_warning_after_ms},
      {DynamicSupervisor, name: Tinkex.ClientSupervisor, strategy: :one_for_one}
    ]
  end

  @doc """
  Returns the default pool size.
  """
  @spec default_pool_size() :: pos_integer()
  def default_pool_size, do: @default_pool_size

  @doc """
  Returns the default pool count.
  """
  @spec default_pool_count() :: pos_integer()
  def default_pool_count, do: @default_pool_count

  defp apply_log_level(env) do
    startup_level = Application.get_env(:tinkex, :log_level) || env.log_level
    Logging.maybe_set_level(startup_level)
  end
end
