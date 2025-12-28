defmodule Pristine.Ports.Semaphore do
  @moduledoc """
  Port for connection/concurrency limiting via semaphores.

  This port provides connection limiting capabilities to prevent
  resource exhaustion when making many concurrent requests.

  ## Use Cases

  - Limiting concurrent HTTP connections to a specific host
  - Preventing thread pool exhaustion in async operations
  - Implementing backpressure in high-throughput systems
  """

  @doc """
  Initialize a named semaphore with a given limit.

  The limit specifies the maximum number of concurrent permits
  that can be held at any given time.
  """
  @callback init(name :: term(), limit :: pos_integer()) :: :ok

  @doc """
  Execute a function while holding a semaphore permit.

  Acquires a permit before executing the function and releases it
  after the function completes (even if it raises an exception).

  Returns `{:error, :timeout}` if the permit cannot be acquired
  within the specified timeout.

  ## Parameters

  - `name` - The semaphore name/identifier
  - `timeout` - Maximum time in milliseconds to wait for a permit,
    or `:infinity` to wait forever
  - `fun` - The zero-arity function to execute
  """
  @callback with_permit(name :: term(), timeout :: timeout(), (-> result)) ::
              result | {:error, :timeout}
            when result: term()

  @doc """
  Attempt to acquire a permit from the semaphore.

  Returns `:ok` if a permit was acquired, or `{:error, :timeout}`
  if the permit could not be acquired within the timeout.
  """
  @callback acquire(name :: term(), timeout :: timeout()) :: :ok | {:error, :timeout}

  @doc """
  Release a previously acquired permit back to the semaphore.
  """
  @callback release(name :: term()) :: :ok

  @doc """
  Get the number of available permits.
  """
  @callback available(name :: term()) :: non_neg_integer()

  @optional_callbacks [init: 2, acquire: 2, release: 1, available: 1]
end
