defmodule Pristine.Ports.BytesSemaphore do
  @moduledoc """
  Port for byte-budget rate limiting via semaphores.

  Unlike count-based semaphores that limit the number of concurrent operations,
  byte-budget semaphores limit the total bytes being processed concurrently.
  This is useful for controlling memory pressure or network bandwidth.

  ## Behavior

  - Acquisitions can push the budget negative to allow in-flight work to complete
  - New acquisitions block while the budget is negative
  - Blocked callers resume once releases bring the budget back to non-negative
  - Waiters are served in FIFO order

  ## Use Cases

  - Limiting concurrent payload sizes in HTTP requests
  - Controlling memory usage in batch processing
  - Implementing backpressure based on data size
  """

  @doc """
  Start a BytesSemaphore process with the given options.

  ## Options

  - `:max_bytes` - Maximum byte budget (default: 5MB)
  - `:name` - Optional name for process registration

  ## Examples

      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 5_000_000)
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1_000, name: MyApp.BytesSemaphore)

  """
  @callback start_link(keyword()) :: GenServer.on_start()

  @doc """
  Acquire bytes from the semaphore, blocking if the budget is negative.

  Returns `:ok` when the bytes have been acquired. If the current budget is
  negative, the caller blocks until enough releases bring it back to non-negative
  or the timeout expires.

  ## Parameters

  - `server` - The semaphore process (pid or registered name)
  - `bytes` - Number of bytes to acquire (non-negative integer)
  - `timeout` - Maximum time in milliseconds to wait, or `:infinity`

  ## Examples

      :ok = BytesSemaphore.acquire(sem, 1000, 5_000)
      {:error, :timeout} = BytesSemaphore.acquire(sem, 1000, 100)

  """
  @callback acquire(
              server :: GenServer.server(),
              bytes :: non_neg_integer(),
              timeout :: timeout()
            ) ::
              :ok | {:error, :timeout}

  @doc """
  Release bytes back to the semaphore.

  This increases the available budget and may wake blocked waiters.

  ## Parameters

  - `server` - The semaphore process (pid or registered name)
  - `bytes` - Number of bytes to release (non-negative integer)

  ## Examples

      :ok = BytesSemaphore.release(sem, 1000)

  """
  @callback release(server :: GenServer.server(), bytes :: non_neg_integer()) :: :ok

  @doc """
  Get the number of available bytes in the budget.

  Returns 0 if the budget is negative.

  ## Parameters

  - `server` - The semaphore process (pid or registered name)

  ## Examples

      available = BytesSemaphore.available(sem)

  """
  @callback available(server :: GenServer.server()) :: non_neg_integer()

  @doc """
  Execute a function while holding the requested byte budget.

  Acquires the bytes, executes the function, and guarantees release even if
  the function raises an exception, throws, or exits.

  ## Parameters

  - `server` - The semaphore process (pid or registered name)
  - `bytes` - Number of bytes to acquire
  - `fun` - Zero-arity function to execute

  ## Examples

      result = BytesSemaphore.with_bytes(sem, 1000, fn ->
        # Work with allocated bytes
        :done
      end)

  """
  @callback with_bytes(server :: GenServer.server(), bytes :: non_neg_integer(), (-> result)) ::
              result
            when result: any()

  @optional_callbacks [with_bytes: 3]
end
