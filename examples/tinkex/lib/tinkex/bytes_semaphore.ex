defmodule Tinkex.BytesSemaphore do
  @moduledoc """
  Byte-budget semaphore for rate limiting by payload size.

  Tracks a shared byte budget across concurrent callers. Acquisitions can push
  the budget negative to allow in-flight work to complete; new acquisitions
  block while the budget is negative and resume once releases bring it back
  to a non-negative value.

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

  ## Negative Budget Behavior

  When the budget goes negative (due to over-acquisition), new callers block
  until enough bytes are released to bring the budget back to non-negative.
  This allows in-flight work to complete while preventing new work from starting.
  """

  use GenServer

  @type t :: pid()

  @default_max_bytes 5 * 1024 * 1024

  @doc """
  Start a BytesSemaphore with the given byte budget.

  ## Options

  - `:max_bytes` - Maximum byte budget (default: 5MB)
  - `:name` - Optional name for registration

  ## Examples

      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1_000_000)
      {:ok, sem} = BytesSemaphore.start_link(name: MyApp.BytesSemaphore)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    GenServer.start_link(__MODULE__, max_bytes, name: Keyword.get(opts, :name))
  end

  @doc """
  Acquire bytes from the semaphore, blocking while the budget is negative.

  Returns `:ok` when the bytes have been acquired. If the current budget is
  negative, the caller blocks until enough releases bring it back to non-negative.

  ## Examples

      :ok = BytesSemaphore.acquire(sem, 1000)

  """
  @spec acquire(t(), non_neg_integer()) :: :ok
  def acquire(semaphore, bytes) when is_integer(bytes) and bytes >= 0 do
    GenServer.call(semaphore, {:acquire, bytes}, :infinity)
  end

  @doc """
  Release bytes back to the semaphore.

  This is an asynchronous operation. If there are blocked waiters and the
  budget returns to non-negative, they will be woken up.

  ## Examples

      :ok = BytesSemaphore.release(sem, 1000)

  """
  @spec release(t(), non_neg_integer()) :: :ok
  def release(semaphore, bytes) when is_integer(bytes) and bytes >= 0 do
    GenServer.cast(semaphore, {:release, bytes})
  end

  @doc """
  Execute `fun` while holding the requested byte budget.

  Acquires the bytes, executes the function, and guarantees release even if
  the function raises an exception, throws, or exits.

  ## Examples

      result = BytesSemaphore.with_bytes(sem, 1000, fn ->
        # Work with allocated bytes
        :done
      end)

  """
  @spec with_bytes(t(), non_neg_integer(), (-> result)) :: result when result: any()
  def with_bytes(semaphore, bytes, fun) when is_function(fun, 0) do
    acquire(semaphore, bytes)

    try do
      fun.()
    after
      release(semaphore, bytes)
    end
  end

  @impl true
  def init(max_bytes) do
    {:ok,
     %{
       max_bytes: max_bytes,
       current_bytes: max_bytes,
       waiters: :queue.new()
     }}
  end

  @impl true
  def handle_call({:acquire, bytes}, from, %{current_bytes: current_bytes} = state)
      when current_bytes < 0 do
    {:noreply, enqueue_waiter(state, from, bytes)}
  end

  def handle_call({:acquire, bytes}, _from, state) do
    {:reply, :ok, %{state | current_bytes: state.current_bytes - bytes}}
  end

  @impl true
  def handle_cast({:release, bytes}, state) do
    state = %{state | current_bytes: state.current_bytes + bytes}
    {:noreply, maybe_wake_waiters(state)}
  end

  defp enqueue_waiter(state, from, bytes) do
    %{state | waiters: :queue.in({from, bytes}, state.waiters)}
  end

  defp maybe_wake_waiters(%{current_bytes: current_bytes} = state) when current_bytes < 0,
    do: state

  defp maybe_wake_waiters(state) do
    case :queue.out(state.waiters) do
      {{:value, {from, bytes}}, remaining} ->
        GenServer.reply(from, :ok)

        state
        |> Map.put(:waiters, remaining)
        |> Map.update!(:current_bytes, &(&1 - bytes))
        |> maybe_wake_waiters()

      {:empty, _} ->
        state
    end
  end
end
