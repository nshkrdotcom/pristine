defmodule Pristine.Adapters.BytesSemaphore.GenServer do
  @moduledoc """
  GenServer-based byte-budget semaphore adapter.

  Tracks a shared byte budget across concurrent callers. Acquisitions can push
  the budget negative to allow in-flight work to complete; new acquisitions
  block while the budget is negative and resume once releases bring it back
  to a non-negative value.

  ## Example

      # Start a semaphore with 5MB budget
      {:ok, sem} = GenServer.start_link(max_bytes: 5_242_880)

      # Acquire bytes (blocks if budget is negative)
      :ok = GenServer.acquire(sem, 1000, 5_000)

      # Do work...

      # Release bytes back
      :ok = GenServer.release(sem, 1000)

  ## with_bytes/3

  For convenience, `with_bytes/3` acquires, executes a function, and guarantees
  release even if the function raises:

      result = GenServer.with_bytes(sem, 1000, fn ->
        # Do work with the allocated bytes
        :ok
      end)
  """

  use Elixir.GenServer

  @behaviour Pristine.Ports.BytesSemaphore

  @type t :: pid() | atom()

  @default_max_bytes 5 * 1024 * 1024

  @impl Pristine.Ports.BytesSemaphore
  @doc """
  Start a BytesSemaphore with the given byte budget.

  ## Options

  - `:max_bytes` - Maximum byte budget (default: 5MB)
  - `:name` - Optional name for registration

  ## Examples

      {:ok, sem} = GenServer.start_link(max_bytes: 1_000_000)
      {:ok, sem} = GenServer.start_link(name: MyApp.BytesSemaphore)

  """
  @spec start_link(keyword()) :: Elixir.GenServer.on_start()
  def start_link(opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    Elixir.GenServer.start_link(__MODULE__, max_bytes, name: Keyword.get(opts, :name))
  end

  @impl Pristine.Ports.BytesSemaphore
  @doc """
  Acquire bytes from the semaphore, blocking while the budget is negative.

  Returns `:ok` when the bytes have been acquired. If the current budget is
  negative, the caller blocks until enough releases bring it back to non-negative
  or the timeout expires.

  ## Examples

      :ok = GenServer.acquire(sem, 1000, 5_000)
      {:error, :timeout} = GenServer.acquire(sem, 1000, 100)

  """
  @spec acquire(t(), non_neg_integer(), timeout()) :: :ok | {:error, :timeout}
  def acquire(semaphore, bytes, timeout) when is_integer(bytes) and bytes >= 0 do
    # Use :infinity for GenServer.call but manage timeout internally via timer
    case timeout do
      :infinity ->
        Elixir.GenServer.call(semaphore, {:acquire, bytes, :infinity}, :infinity)

      timeout_ms when is_integer(timeout_ms) ->
        Elixir.GenServer.call(semaphore, {:acquire, bytes, timeout_ms}, timeout_ms + 100)
    end
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @impl Pristine.Ports.BytesSemaphore
  @doc """
  Release bytes back to the semaphore.

  This is an asynchronous operation. If there are blocked waiters and the
  budget returns to non-negative, they will be woken up.

  ## Examples

      :ok = GenServer.release(sem, 1000)

  """
  @spec release(t(), non_neg_integer()) :: :ok
  def release(semaphore, bytes) when is_integer(bytes) and bytes >= 0 do
    Elixir.GenServer.cast(semaphore, {:release, bytes})
  end

  @impl Pristine.Ports.BytesSemaphore
  @doc """
  Get the number of available bytes.

  Returns 0 if the budget is negative.

  ## Examples

      available = GenServer.available(sem)

  """
  @spec available(t()) :: non_neg_integer()
  def available(semaphore) do
    Elixir.GenServer.call(semaphore, :available)
  end

  @impl Pristine.Ports.BytesSemaphore
  @doc """
  Execute `fun` while holding the requested byte budget.

  Acquires the bytes, executes the function, and guarantees release even if
  the function raises an exception, throws, or exits.

  ## Examples

      result = GenServer.with_bytes(sem, 1000, fn ->
        # Work with allocated bytes
        :done
      end)

  """
  @spec with_bytes(t(), non_neg_integer(), (-> result)) :: result when result: any()
  def with_bytes(semaphore, bytes, fun) when is_function(fun, 0) do
    :ok = acquire(semaphore, bytes, :infinity)

    try do
      fun.()
    after
      release(semaphore, bytes)
    end
  end

  # GenServer callbacks

  @impl Elixir.GenServer
  def init(max_bytes) do
    {:ok,
     %{
       max_bytes: max_bytes,
       current_bytes: max_bytes,
       waiters: :queue.new()
     }}
  end

  @impl Elixir.GenServer
  def handle_call({:acquire, bytes, timeout}, from, %{current_bytes: current_bytes} = state)
      when current_bytes < 0 do
    # Budget is negative, enqueue waiter with timer
    state = enqueue_waiter(state, from, bytes, timeout)
    {:noreply, state}
  end

  def handle_call({:acquire, bytes, _timeout}, _from, state) do
    # Budget is non-negative, immediately acquire
    {:reply, :ok, %{state | current_bytes: state.current_bytes - bytes}}
  end

  def handle_call(:available, _from, state) do
    {:reply, max(0, state.current_bytes), state}
  end

  @impl Elixir.GenServer
  def handle_cast({:release, bytes}, state) do
    state = %{state | current_bytes: state.current_bytes + bytes}
    {:noreply, maybe_wake_waiters(state)}
  end

  @impl Elixir.GenServer
  def handle_info({:timeout, timer_ref, from}, state) do
    # Remove the timed-out waiter from the queue
    state = remove_waiter(state, from, timer_ref)
    # Reply with timeout error
    Elixir.GenServer.reply(from, {:error, :timeout})
    {:noreply, state}
  end

  # Private functions

  defp enqueue_waiter(state, from, bytes, timeout) do
    timer_ref =
      case timeout do
        :infinity -> nil
        timeout_ms -> :erlang.start_timer(timeout_ms, self(), from)
      end

    waiter = {from, bytes, timer_ref}
    %{state | waiters: :queue.in(waiter, state.waiters)}
  end

  defp remove_waiter(state, target_from, timer_ref) do
    # Cancel the timer if it exists
    if timer_ref, do: :erlang.cancel_timer(timer_ref)

    # Filter out the waiter with matching from
    new_waiters =
      state.waiters
      |> :queue.to_list()
      |> Enum.reject(fn {from, _bytes, _ref} -> from == target_from end)
      |> :queue.from_list()

    %{state | waiters: new_waiters}
  end

  defp maybe_wake_waiters(%{current_bytes: current_bytes} = state) when current_bytes < 0,
    do: state

  defp maybe_wake_waiters(state) do
    case :queue.out(state.waiters) do
      {{:value, {from, bytes, timer_ref}}, remaining} ->
        # Cancel the timeout timer if it exists
        if timer_ref, do: :erlang.cancel_timer(timer_ref)

        Elixir.GenServer.reply(from, :ok)

        state
        |> Map.put(:waiters, remaining)
        |> Map.update!(:current_bytes, &(&1 - bytes))
        |> maybe_wake_waiters()

      {:empty, _} ->
        state
    end
  end
end
