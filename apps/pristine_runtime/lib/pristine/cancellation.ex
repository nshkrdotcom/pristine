defmodule Pristine.Cancellation do
  @moduledoc """
  Opaque, process-safe cancellation token for a logical unary request.

  A token starts active and becomes permanently cancelled after `cancel/1`.
  Cancellation is idempotent and may be triggered from any BEAM process.

  The token is a one-shot lifecycle signal. It may be intentionally shared by
  multiple related requests, but once cancelled it can never be reset or reused
  as an active token. Cancelling it does not roll back a remote side effect and
  does not prove that an upstream service never received or started processing a
  request.
  """

  @registry Pristine.Cancellation.Registry
  @cancelled 1
  @active 0

  @derive {Inspect, only: []}
  @enforce_keys [:id, :state]
  defstruct [:id, :state]

  @opaque t :: %__MODULE__{id: reference(), state: term()}
  @type await_result :: :cancelled | :timeout

  @doc """
  Create a new active cancellation token.
  """
  @spec new() :: t()
  def new do
    state = :atomics.new(1, signed: false)
    :ok = :atomics.put(state, 1, @active)
    %__MODULE__{id: make_ref(), state: state}
  end

  @doc """
  Permanently cancel a token.

  The first caller transitions the token and wakes current waiters. Repeated or
  concurrent calls are harmless and return `:ok`.
  """
  @spec cancel(t()) :: :ok
  def cancel(%__MODULE__{} = cancellation) do
    case :atomics.exchange(cancellation.state, 1, @cancelled) do
      @active -> notify_waiters(cancellation)
      @cancelled -> :ok
    end
  end

  @doc """
  Return whether the token has been cancelled.
  """
  @spec cancelled?(t()) :: boolean()
  def cancelled?(%__MODULE__{} = cancellation) do
    :atomics.get(cancellation.state, 1) == @cancelled
  end

  @doc """
  Wait for cancellation for up to `timeout` milliseconds.

  Returns `:cancelled` as soon as cancellation is observed or `:timeout` when
  the supplied timeout expires. Waiting does not consume the token; cancellation
  remains terminal and observable by later callers.
  """
  @spec await(t(), timeout()) :: await_result()
  def await(cancellation, timeout \\ :infinity)

  def await(%__MODULE__{} = cancellation, timeout)
      when timeout == :infinity or (is_integer(timeout) and timeout >= 0) do
    if cancelled?(cancellation) do
      :cancelled
    else
      await_registered(cancellation, timeout)
    end
  end

  @doc false
  @spec validate(term()) :: {:ok, t()} | :error
  def validate(%__MODULE__{} = token), do: {:ok, token}
  def validate(_), do: :error

  @doc false
  @spec watch(t(), (-> term())) :: {Task.t(), reference()}
  def watch(%__MODULE__{} = cancellation, on_cancel) do
    stop = make_ref()

    task =
      Task.async(fn ->
        case await_registered(cancellation, :infinity, stop) do
          :cancelled -> on_cancel.()
          :stopped -> :ok
        end
      end)

    {task, stop}
  end

  @doc false
  def stop_watcher({task, stop}) do
    send(task.pid, {:stop_cancellation_watcher, stop})
    Task.await(task, :infinity)
  end

  defp await_registered(cancellation, timeout, stop \\ nil) do
    subscription = :erlang.alias()

    case register_waiter(cancellation, subscription) do
      :ok ->
        try do
          if cancelled?(cancellation) do
            flush_signal(cancellation, subscription)
            :cancelled
          else
            receive do
              {@registry, id, ^subscription, :cancelled} when id == cancellation.id ->
                :cancelled

              {:stop_cancellation_watcher, ^stop} when is_reference(stop) ->
                :stopped
            after
              timeout -> :timeout
            end
          end
        after
          :erlang.unalias(subscription)
          unregister_waiter(cancellation)
          flush_signal(cancellation, subscription)
        end

      :registry_unavailable ->
        :erlang.unalias(subscription)
        await_without_registry(cancellation, timeout)
    end
  end

  defp register_waiter(cancellation, subscription) do
    case Process.whereis(@registry) do
      pid when is_pid(pid) ->
        case Registry.register(@registry, cancellation.id, subscription) do
          {:ok, _owner} -> :ok
          {:error, {:already_registered, _pid}} -> :ok
        end

      nil ->
        :registry_unavailable
    end
  end

  defp unregister_waiter(cancellation) do
    if Process.whereis(@registry), do: Registry.unregister(@registry, cancellation.id)
    :ok
  end

  # Direct token use before the Pristine application has started still remains
  # safe. This path intentionally uses small receive timeouts instead of creating
  # a token-owned process or ETS table.
  defp await_without_registry(cancellation, :infinity) do
    if cancelled?(cancellation) do
      :cancelled
    else
      receive do
      after
        10 -> await_without_registry(cancellation, :infinity)
      end
    end
  end

  defp await_without_registry(cancellation, timeout) when timeout <= 10 do
    receive do
    after
      timeout -> if(cancelled?(cancellation), do: :cancelled, else: :timeout)
    end
  end

  defp await_without_registry(cancellation, timeout) do
    receive do
    after
      10 ->
        if cancelled?(cancellation) do
          :cancelled
        else
          await_without_registry(cancellation, timeout - 10)
        end
    end
  end

  defp notify_waiters(cancellation) do
    case Process.whereis(@registry) do
      pid when is_pid(pid) ->
        Registry.dispatch(@registry, cancellation.id, fn entries ->
          notify_entries(entries, cancellation.id)
        end)

        :ok

      nil ->
        :ok
    end
  end

  defp notify_entries(entries, id) do
    Enum.each(entries, fn {_waiter, subscription} ->
      send(subscription, {@registry, id, subscription, :cancelled})
    end)
  end

  defp flush_signal(cancellation, subscription) do
    receive do
      {@registry, id, ^subscription, :cancelled} when id == cancellation.id -> :ok
    after
      0 -> :ok
    end
  end
end
