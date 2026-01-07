defmodule Pristine.Adapters.Semaphore.Counting do
  @moduledoc """
  Counting semaphore adapter using Foundation.Semaphore.Counting.

  This adapter provides connection/concurrency limiting using an ETS-backed
  counting semaphore. It's designed for limiting concurrent HTTP connections
  or other resource access patterns.

  ## Example

      # Initialize a semaphore with a limit of 10 concurrent operations
      Counting.init(:http_pool, 10)

      # Execute a function while holding a permit
      result = Counting.with_permit(:http_pool, 5_000, fn ->
        make_http_request()
      end)

      # Handle timeout
      case Counting.with_permit(:http_pool, 100, fn -> slow_operation() end) do
        {:error, :timeout} -> {:error, :too_busy}
        result -> result
      end
  """

  @behaviour Pristine.Ports.Semaphore

  alias Foundation.Semaphore.Counting, as: FoundationSemaphore

  # ETS table to store semaphore configuration (name -> limit)
  @config_table __MODULE__.Config
  # Named registry for semaphore counts
  @registry_table __MODULE__.Registry

  @impl true
  @doc """
  Initialize a named semaphore with a given limit.

  The semaphore will be created in the adapter's registry
  and its limit will be stored for later reference.
  """
  def init(name, limit) when is_integer(limit) and limit > 0 do
    ensure_tables()
    :ets.insert(@config_table, {name, limit})
    :ok
  end

  @impl true
  @doc """
  Execute a function while holding a semaphore permit.

  Acquires a permit, executes the function, and releases the permit.
  If the permit cannot be acquired within the timeout, returns `{:error, :timeout}`.
  The permit is always released, even if the function raises an exception.
  """
  def with_permit(name, timeout, fun) when is_function(fun, 0) do
    case acquire(name, timeout) do
      :ok ->
        try do
          fun.()
        after
          release(name)
        end

      {:error, :timeout} = error ->
        error
    end
  end

  @impl true
  @doc """
  Attempt to acquire a permit from the semaphore.

  Uses a spin-wait loop with short sleeps to attempt acquisition
  within the specified timeout.
  """
  def acquire(name, timeout) do
    limit = get_limit(name)
    registry = ensure_registry()

    deadline =
      if timeout == :infinity, do: :infinity, else: System.monotonic_time(:millisecond) + timeout

    do_acquire(registry, name, limit, deadline)
  end

  @impl true
  @doc """
  Release a previously acquired permit back to the semaphore.
  """
  def release(name) do
    registry = ensure_registry()
    FoundationSemaphore.release(registry, name)
  end

  @impl true
  def acquire_blocking(registry, name, max, backoff, opts \\ []) do
    FoundationSemaphore.acquire_blocking(registry, name, max, backoff, opts)
  end

  @impl true
  def release(registry, name) do
    FoundationSemaphore.release(registry, name)
  end

  @impl true
  @doc """
  Get the number of available permits.

  Returns the difference between the configured limit and the current count.
  """
  def available(name) do
    limit = get_limit(name)
    registry = ensure_registry()
    current = FoundationSemaphore.count(registry, name)
    max(0, limit - current)
  end

  # Private functions

  defp ensure_tables do
    ensure_config_table()
    ensure_registry()
    :ok
  end

  defp ensure_config_table do
    case :ets.whereis(@config_table) do
      :undefined ->
        :ets.new(@config_table, [:set, :public, :named_table, {:read_concurrency, true}])

      _tid ->
        :ok
    end
  end

  defp ensure_registry do
    # Use a named ETS table for the registry to avoid persistent_term staleness issues
    case :ets.whereis(@registry_table) do
      :undefined ->
        FoundationSemaphore.new_registry(name: @registry_table)

      _tid ->
        @registry_table
    end
  end

  defp get_limit(name) do
    ensure_config_table()

    case :ets.lookup(@config_table, name) do
      [{^name, limit}] -> limit
      [] -> raise ArgumentError, "Semaphore #{inspect(name)} not initialized. Call init/2 first."
    end
  end

  defp do_acquire(registry, name, limit, deadline) do
    if FoundationSemaphore.acquire(registry, name, limit) do
      :ok
    else
      if past_deadline?(deadline) do
        {:error, :timeout}
      else
        # Short sleep before retrying
        Process.sleep(1)
        do_acquire(registry, name, limit, deadline)
      end
    end
  end

  defp past_deadline?(:infinity), do: false

  defp past_deadline?(deadline) do
    System.monotonic_time(:millisecond) >= deadline
  end
end
