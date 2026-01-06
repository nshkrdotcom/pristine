defmodule Tinkex.Semaphore do
  @moduledoc """
  Named counting semaphore for concurrency limiting.

  Provides a global named semaphore service where different keys can have
  independent counts and limits. This is used by SamplingDispatch for
  concurrency and throttled semaphores.

  ## Usage

      # Start the semaphore service (typically in application supervision tree)
      {:ok, _} = Semaphore.start_link()

      # Acquire a permit - returns true if under limit, false otherwise
      if Semaphore.acquire(:my_resource, 10) do
        try do
          # Do work...
        after
          Semaphore.release(:my_resource)
        end
      else
        # At limit, retry later
      end

  ## Key Features

  - Non-blocking acquire (returns immediately with true/false)
  - Named keys for independent resource pools
  - Dynamic limits (can be changed per acquire call)
  - Thread-safe concurrent access
  """

  use GenServer

  @type key :: any()

  @doc """
  Start the semaphore service.

  The service is registered under the module name `Tinkex.Semaphore`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Try to acquire a permit for the given key.

  Returns `true` if the current count is below the limit and the permit was
  acquired. Returns `false` if the limit has been reached.

  The limit can vary between calls - the current count is checked against
  the limit provided in each call.

  ## Examples

      Semaphore.acquire(:api_requests, 100)  # => true
      Semaphore.acquire(:api_requests, 100)  # => true
      # ... 98 more acquires ...
      Semaphore.acquire(:api_requests, 100)  # => false (at limit)

  """
  @spec acquire(key(), pos_integer()) :: boolean()
  def acquire(key, limit) when is_integer(limit) and limit > 0 do
    GenServer.call(__MODULE__, {:acquire, key, limit})
  end

  @doc """
  Release a permit for the given key.

  Decrements the count for the key. If the count is already zero,
  this is a no-op.

  ## Examples

      Semaphore.release(:api_requests)

  """
  @spec release(key()) :: :ok
  def release(key) do
    GenServer.cast(__MODULE__, {:release, key})
  end

  @doc """
  Get the current count for a key.

  Returns the number of currently held permits for the given key.

  ## Examples

      Semaphore.count(:api_requests)  # => 42

  """
  @spec count(key()) :: non_neg_integer()
  def count(key) do
    GenServer.call(__MODULE__, {:count, key})
  end

  # GenServer callbacks

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:acquire, key, limit}, _from, state) do
    current = Map.get(state, key, 0)

    if current < limit do
      {:reply, true, Map.put(state, key, current + 1)}
    else
      {:reply, false, state}
    end
  end

  def handle_call({:count, key}, _from, state) do
    {:reply, Map.get(state, key, 0), state}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{}}
  end

  @impl true
  def handle_cast({:release, key}, state) do
    current = Map.get(state, key, 0)
    new_count = max(current - 1, 0)
    {:noreply, Map.put(state, key, new_count)}
  end
end
