defmodule Tinkex.BytesSemaphore do
  @moduledoc """
  Byte-budget semaphore for rate limiting by payload size.

  This is a thin wrapper around `Pristine.Adapters.BytesSemaphore.GenServer`
  that maintains Tinkex's original API for backwards compatibility.

  ## Usage

      # Start a semaphore with 5MB budget
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 5_242_880)

      # Acquire bytes (blocks if budget is negative)
      :ok = BytesSemaphore.acquire(sem, 1000)

      # Do work...

      # Release bytes back
      BytesSemaphore.release(sem, 1000)

  ## with_bytes/3

  For convenience, `with_bytes/3` acquires, executes a function, and guarantees
  release even if the function raises:

      result = BytesSemaphore.with_bytes(sem, 1000, fn ->
        # Do work with the allocated bytes
        :ok
      end)
  """

  alias Pristine.Adapters.BytesSemaphore.GenServer, as: PristineSemaphore

  @type t :: pid()

  defdelegate start_link(opts \\ []), to: PristineSemaphore

  @doc """
  Acquire bytes from the semaphore, blocking indefinitely while the budget is negative.
  """
  @spec acquire(t(), non_neg_integer()) :: :ok
  def acquire(semaphore, bytes) do
    :ok = PristineSemaphore.acquire(semaphore, bytes, :infinity)
  end

  defdelegate release(semaphore, bytes), to: PristineSemaphore

  defdelegate with_bytes(semaphore, bytes, fun), to: PristineSemaphore
end
