defmodule Pristine.RuntimeGateway.Local.StreamWorker do
  @moduledoc false

  use GenServer, restart: :temporary

  alias ExecutionPlane.{ActiveExecution, Boundary}
  alias ExecutionPlane.Runtime.{Error, Event, Status}
  alias Pristine.Adapters.Transport.FinchStream
  alias Pristine.Core.StreamResponse

  @registry Pristine.RuntimeGateway.Registry
  @terminal_states ActiveExecution.terminal_states()

  defstruct [
    :active,
    :credits,
    :error,
    :max_demand,
    :pending,
    :receipt_ref,
    :response,
    :runner,
    :runner_monitor,
    :sequence,
    :subscriber,
    :subscriber_monitor,
    :terminal_retention_ms
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    execution_ref = Keyword.fetch!(opts, :execution_ref)
    name = {:via, Registry, {@registry, execution_ref.ref}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :execution_ref).ref},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @spec active(pid()) :: {:ok, ActiveExecution.t()} | {:error, term()}
  def active(pid), do: GenServer.call(pid, :active)

  @spec demand(pid(), pos_integer()) :: :ok | {:error, Error.t()}
  def demand(pid, credits), do: GenServer.call(pid, {:demand, credits})

  @spec status(pid()) :: {:ok, Status.t()}
  def status(pid), do: GenServer.call(pid, :status)

  @spec cancel(pid()) :: :ok
  def cancel(pid), do: GenServer.call(pid, :cancel)

  @impl true
  def init(opts) do
    validated = Keyword.fetch!(opts, :validated)
    context = validated.context
    request = validated.request
    stream_transport = context.stream_transport || FinchStream

    case stream_transport.stream(request, context) do
      {:ok, %StreamResponse{} = response} ->
        execution_ref = Keyword.fetch!(opts, :execution_ref)
        subscriber = Keyword.fetch!(opts, :subscriber)

        active =
          ActiveExecution.new!(
            execution_ref: execution_ref,
            session_ref: "pristine-http-local://#{execution_ref.ref}",
            admission_decision_ref: "direct://pristine/http/#{execution_ref.ref}",
            node_id: "local",
            lane_id: "http",
            state: "running",
            started_at: DateTime.utc_now(),
            fence: 0
          )

        state = %__MODULE__{
          active: active,
          credits: 0,
          error: nil,
          max_demand: positive_option(opts, :max_demand, 16),
          pending: nil,
          receipt_ref: nil,
          response: response,
          runner: nil,
          runner_monitor: nil,
          sequence: 0,
          subscriber: subscriber,
          subscriber_monitor: Process.monitor(subscriber),
          terminal_retention_ms: positive_option(opts, :terminal_retention_ms, 30_000)
        }

        {:ok, state, {:continue, :start_stream}}

      {:error, %Error{} = error} ->
        {:stop, error}

      {:error, _reason} ->
        {:stop,
         Error.new!(
           category: "unavailable",
           message: "local HTTP stream transport could not start",
           retryable: true,
           ambiguous: false
         )}
    end
  end

  @impl true
  def handle_continue(:start_stream, state) do
    state =
      publish(state, "started", %{
        "placement" => "local_effect",
        "status" => state.response.status,
        "headers" => state.response.headers
      })

    owner = self()

    {runner, runner_monitor} =
      spawn_monitor(fn -> enumerate_stream(state.response.stream, owner) end)

    {:noreply, %{state | runner: runner, runner_monitor: runner_monitor}}
  end

  @impl true
  def handle_call(:active, _from, state), do: {:reply, {:ok, state.active}, state}

  def handle_call({:demand, _credits}, _from, state)
      when state.active.state in @terminal_states do
    {:reply, {:error, terminal_error()}, state}
  end

  def handle_call({:demand, credits}, _from, state)
      when is_integer(credits) and credits > 0 do
    if state.credits + credits > state.max_demand do
      {:reply, {:error, backpressure_error()}, state}
    else
      state = %{state | credits: state.credits + credits}
      {:reply, :ok, release_pending(state)}
    end
  end

  def handle_call(:status, _from, state), do: {:reply, {:ok, runtime_status(state)}, state}

  def handle_call(:cancel, _from, state) when state.active.state in @terminal_states do
    {:reply, :ok, state}
  end

  def handle_call(:cancel, _from, state) do
    state = cancel_transport(state)
    state = finish(state, "cancelled", cancelled_error())
    {:reply, :ok, state}
  end

  def handle_call({:emit, _event}, _from, state)
      when state.active.state in @terminal_states do
    {:reply, {:error, terminal_error()}, state}
  end

  def handle_call({:emit, event}, _from, %{credits: credits} = state) when credits > 0 do
    state = publish_output(%{state | credits: credits - 1}, event)
    {:reply, :ok, state}
  end

  def handle_call({:emit, event}, from, state) do
    state =
      state
      |> transition("backpressured")
      |> publish("backpressure", %{
        "placement" => "local_effect",
        "available_credits" => 0,
        "max_demand" => state.max_demand
      })

    {:noreply, %{state | pending: {from, event}}}
  end

  @impl true
  def handle_cast(:source_done, state) when state.active.state in @terminal_states,
    do: {:noreply, state}

  def handle_cast(:source_done, state) do
    {:noreply, finish(state, "completed", nil)}
  end

  def handle_cast(:source_failed, state) when state.active.state in @terminal_states,
    do: {:noreply, state}

  def handle_cast(:source_failed, state) do
    error =
      Error.new!(
        category: "transport_lost",
        message: "local HTTP stream transport failed",
        retryable: true,
        ambiguous: false
      )

    {:noreply, finish(state, "failed", error)}
  end

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{subscriber_monitor: monitor} = state
      ) do
    state =
      if state.active.state in @terminal_states do
        state
      else
        state |> cancel_transport() |> finish("cancelled", cancelled_error())
      end

    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, %{runner_monitor: monitor} = state) do
    cond do
      state.active.state in @terminal_states ->
        {:noreply, state}

      reason == :normal ->
        {:noreply, finish(state, "completed", nil)}

      true ->
        GenServer.cast(self(), :source_failed)
        {:noreply, state}
    end
  end

  def handle_info(:cleanup, state), do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, state) do
    if state.active.state not in @terminal_states do
      _ = StreamResponse.cancel(state.response)
    end

    :ok
  end

  defp enumerate_stream(stream, owner) do
    _ =
      Enum.reduce_while(stream, :ok, fn event, :ok ->
        case GenServer.call(owner, {:emit, event}, :infinity) do
          :ok -> {:cont, :ok}
          {:error, _reason} -> {:halt, :ok}
        end
      end)

    GenServer.cast(owner, :source_done)
  rescue
    _exception -> GenServer.cast(owner, :source_failed)
  catch
    :exit, _reason -> :ok
  end

  defp release_pending(%{pending: nil} = state), do: transition(state, "running")

  defp release_pending(%{pending: {from, event}, credits: credits} = state) when credits > 0 do
    GenServer.reply(from, :ok)

    state
    |> Map.put(:pending, nil)
    |> Map.put(:credits, credits - 1)
    |> transition("running")
    |> publish_output(event)
  end

  defp publish_output(state, event) do
    publish(state, "output", %{
      "placement" => "local_effect",
      "event" => Boundary.dump_value(event)
    })
  end

  defp finish(state, terminal_state, error) do
    receipt_ref = "receipt://pristine/local/#{state.active.execution_ref.ref}/#{terminal_state}"

    if state.pending do
      {from, _event} = state.pending
      GenServer.reply(from, {:error, error || terminal_error()})
    end

    state =
      state
      |> Map.put(:pending, nil)
      |> Map.put(:credits, 0)
      |> Map.put(:error, error)
      |> Map.put(:receipt_ref, receipt_ref)
      |> transition(terminal_state, receipt_ref)
      |> publish("receipt", %{
        "placement" => "local_effect",
        "receipt_ref" => receipt_ref,
        "state" => terminal_state
      })

    Process.send_after(self(), :cleanup, state.terminal_retention_ms)
    state
  end

  defp transition(%{active: %ActiveExecution{} = active} = state, next_state, receipt_ref \\ nil) do
    %{state | active: %{active | state: next_state, receipt_ref: receipt_ref}}
  end

  defp publish(state, kind, payload) do
    sequence = state.sequence + 1

    event =
      Event.new!(
        execution_ref: state.active.execution_ref,
        sequence: sequence,
        kind: kind,
        emitted_at: DateTime.utc_now(),
        payload: payload
      )

    send(state.subscriber, event)
    %{state | sequence: sequence}
  end

  defp runtime_status(state) do
    terminal? = state.active.state in @terminal_states

    Status.new!(
      execution_ref: state.active.execution_ref,
      state: state.active.state,
      sequence: state.sequence,
      input_open: not terminal?,
      output_open: not terminal?,
      receipt_ref: state.receipt_ref,
      error: state.error
    )
  end

  defp cancel_transport(state) do
    _ = StreamResponse.cancel(state.response)

    if is_pid(state.runner) and Process.alive?(state.runner) do
      Process.exit(state.runner, :shutdown)
    end

    state
  end

  defp positive_option(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end

  defp backpressure_error do
    Error.new!(
      category: "backpressure",
      message: "HTTP stream demand exceeds the bounded credit window",
      retryable: true,
      ambiguous: false
    )
  end

  defp cancelled_error do
    Error.new!(
      category: "cancelled",
      message: "HTTP stream was cancelled",
      retryable: false,
      ambiguous: false
    )
  end

  defp terminal_error do
    Error.new!(
      category: "terminal",
      message: "HTTP stream is terminal",
      retryable: false,
      ambiguous: false
    )
  end
end
