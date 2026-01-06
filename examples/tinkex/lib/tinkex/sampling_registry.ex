defmodule Tinkex.SamplingRegistry do
  @moduledoc """
  Registry that tracks SamplingClient processes and cleans up ETS entries on exit.

  The registry monitors registered processes and automatically cleans up their
  ETS entries when they terminate. This ensures proper resource cleanup for
  sampling clients.

  ## Usage

      # Start the registry (typically done in Application supervisor)
      {:ok, _pid} = Tinkex.SamplingRegistry.start_link()

      # Register a sampling client process
      Tinkex.SamplingRegistry.register(self(), %{model: "gpt-4"})

      # When the registered process exits, its ETS entry is automatically cleaned up

  ## ETS Table

  Uses the `:tinkex_sampling_clients` ETS table with keys of the form
  `{:config, pid}` to store client configurations.
  """

  use GenServer

  @ets_table :tinkex_sampling_clients

  @type state :: %{monitors: %{reference() => pid()}}

  @doc """
  Start the registry.

  ## Options

  - `:name` - Process name (default: `Tinkex.SamplingRegistry`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Register a SamplingClient process with its configuration payload.

  The process will be monitored and its ETS entry will be automatically
  cleaned up when it terminates.
  """
  @spec register(pid(), map()) :: :ok
  def register(pid, config) when is_pid(pid) and is_map(config) do
    GenServer.call(__MODULE__, {:register, pid, config})
  end

  @doc """
  Get the configuration for a registered process.
  """
  @spec get_config(pid()) :: {:ok, map()} | :error
  def get_config(pid) when is_pid(pid) do
    case :ets.lookup(@ets_table, {:config, pid}) do
      [{{:config, ^pid}, config}] -> {:ok, config}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end

  @doc """
  List all registered process PIDs.
  """
  @spec list_pids() :: [pid()]
  def list_pids do
    @ets_table
    |> :ets.tab2list()
    |> Enum.map(fn {{:config, pid}, _config} -> pid end)
  rescue
    ArgumentError -> []
  end

  # GenServer callbacks

  @impl true
  def init(:ok) do
    ensure_ets_table()
    {:ok, %{monitors: %{}}}
  end

  @impl true
  def handle_call({:register, pid, config}, _from, state) do
    ref = Process.monitor(pid)

    try do
      :ets.insert(@ets_table, {{:config, pid}, config})
    rescue
      ArgumentError -> :ok
    end

    {:reply, :ok, %{state | monitors: Map.put(state.monitors, ref, pid)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {pid, monitors} ->
        try do
          :ets.delete(@ets_table, {:config, pid})
        rescue
          ArgumentError -> :ok
        end

        {:noreply, %{state | monitors: monitors}}
    end
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  # Private helpers

  defp ensure_ets_table do
    :ets.new(@ets_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
  rescue
    ArgumentError -> @ets_table
  end
end
