defmodule Pristine.RuntimeGateway.Local do
  @moduledoc """
  Same-node HTTP-family gateway.

  Unary requests use the already-selected Pristine transport. Incremental
  requests run in an owned worker with explicit demand, a bounded credit
  window, real transport cancellation, terminal receipts, and cleanup.
  """

  @behaviour Pristine.RuntimeGateway

  alias ExecutionPlane.{ExecutionRef, ExecutionResult, Provenance}
  alias ExecutionPlane.Runtime.Error
  alias Pristine.Adapters.Transport.Finch
  alias Pristine.Core.Response
  alias Pristine.RuntimeGateway.{Local.StreamWorker, Materialization}

  @registry Pristine.RuntimeGateway.Registry
  @supervisor Pristine.RuntimeGateway.StreamSupervisor

  @default_max_demand 16
  @default_terminal_retention_ms 30_000

  @impl true
  def unary(family_request, opts) do
    with {:ok, validated} <- Materialization.validate(family_request, opts, :unary),
         {:ok, %Response{} = response} <- send_unary(validated) do
      execution_ref = ExecutionRef.new!()

      {:ok,
       ExecutionResult.new!(
         execution_ref: execution_ref,
         status: "succeeded",
         output: %{
           "placement" => "local_effect",
           "response" => %{
             "status" => response.status,
             "headers" => response.headers,
             "body" => response.body
           }
         },
         provenance: Provenance.direct_lower_lane_owner("pristine")
       )}
    end
  end

  @impl true
  def stream(family_request, subscriber, opts) when is_pid(subscriber) and is_list(opts) do
    with {:ok, validated} <- Materialization.validate(family_request, opts, :incremental),
         {:ok, max_demand} <-
           positive_option(opts, :max_demand, @default_max_demand, "stream max_demand"),
         {:ok, terminal_retention_ms} <-
           positive_option(
             opts,
             :terminal_retention_ms,
             @default_terminal_retention_ms,
             "stream terminal_retention_ms"
           ),
         :ok <- ensure_stream_runtime(),
         execution_ref <- ExecutionRef.new!(),
         worker_opts <-
           [
             execution_ref: execution_ref,
             subscriber: subscriber,
             validated: validated,
             max_demand: max_demand,
             terminal_retention_ms: terminal_retention_ms
           ],
         {:ok, pid} <- DynamicSupervisor.start_child(@supervisor, {StreamWorker, worker_opts}) do
      StreamWorker.active(pid)
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, unavailable_error(reason)}
    end
  end

  def stream(_family_request, _subscriber, _opts) do
    {:error,
     Error.new!(
       category: "invalid_request",
       message: "stream subscriber and options are invalid",
       retryable: false,
       ambiguous: false
     )}
  end

  @impl true
  def demand(execution_ref, credits, _opts) when is_integer(credits) and credits > 0 do
    with {:ok, pid} <- lookup(execution_ref) do
      call_worker(fn -> StreamWorker.demand(pid, credits) end)
    end
  end

  def demand(_execution_ref, _credits, _opts) do
    {:error,
     Error.new!(
       category: "invalid_request",
       message: "stream demand must be a positive integer",
       retryable: false,
       ambiguous: false
     )}
  end

  @impl true
  def status(execution_ref, _opts) do
    with {:ok, pid} <- lookup(execution_ref) do
      call_worker(fn -> StreamWorker.status(pid) end)
    end
  end

  @impl true
  def cancel(execution_ref, _opts) do
    with {:ok, pid} <- lookup(execution_ref) do
      call_worker(fn -> StreamWorker.cancel(pid) end)
    end
  end

  defp send_unary(%{context: context, request: request}) do
    transport = context.transport || Finch
    transport.send(request, context)
  end

  defp ensure_stream_runtime do
    if Process.whereis(@supervisor) && Process.whereis(@registry) do
      :ok
    else
      {:error, :runtime_not_started}
    end
  end

  defp lookup(%ExecutionRef{ref: ref}), do: lookup(ref)

  defp lookup(ref) when is_binary(ref) do
    case Registry.lookup(@registry, ref) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, unknown_execution_error()}
    end
  catch
    :exit, _reason -> {:error, unavailable_error(:registry_unavailable)}
  end

  defp lookup(_ref), do: {:error, unknown_execution_error()}

  defp unknown_execution_error do
    Error.new!(
      category: "invalid_request",
      message: "HTTP stream execution reference is unknown",
      retryable: false,
      ambiguous: false
    )
  end

  defp unavailable_error(%Error{} = error), do: error

  defp unavailable_error(_reason) do
    Error.new!(
      category: "unavailable",
      message: "local HTTP stream runtime is unavailable",
      retryable: true,
      ambiguous: false
    )
  end

  defp call_worker(fun) do
    fun.()
  catch
    :exit, _reason -> {:error, unknown_execution_error()}
  end

  defp positive_option(opts, key, default, label) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      _other ->
        {:error,
         Error.new!(
           category: "invalid_request",
           message: "#{label} must be a positive integer",
           retryable: false,
           ambiguous: false
         )}
    end
  end
end
