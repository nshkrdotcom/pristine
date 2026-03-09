defmodule Pristine.Adapters.Semaphore.Counting.Owner do
  @moduledoc false

  use GenServer

  @config_table Pristine.Adapters.Semaphore.Counting.Config
  @registry_table Pristine.Adapters.Semaphore.Counting.Registry

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @spec ensure_started() :: :ok
  def ensure_started do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end
    end
  end

  @impl GenServer
  def init(:ok) do
    ensure_table(@config_table, [:set, :public, :named_table, {:read_concurrency, true}])

    ensure_table(
      @registry_table,
      [:set, :public, :named_table, {:read_concurrency, true}, {:write_concurrency, true}]
    )

    {:ok, %{}}
  end

  defp ensure_table(name, options) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, options)
      _tid -> name
    end
  end
end
