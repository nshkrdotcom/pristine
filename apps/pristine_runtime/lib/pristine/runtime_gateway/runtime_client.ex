defmodule Pristine.RuntimeGateway.RuntimeClient do
  @moduledoc """
  HTTP-family gateway backed only by an injected Execution Plane Runtime Client.

  This module never delegates to the local gateway. It validates endpoint and
  family bindings before dispatch, requires complete governed admission
  material, and identifies admitted placement only after `Runtime.Client.start/2`
  succeeds.
  """

  @behaviour Pristine.RuntimeGateway

  alias ExecutionPlane.Admission.Request, as: AdmissionRequest
  alias ExecutionPlane.{ActiveExecution, ExecutionRef, ExecutionResult, Provenance}
  alias ExecutionPlane.Runtime.{Error, Event}
  alias Pristine.RuntimeGateway.Materialization

  @impl true
  def unary(family_request, opts) do
    with {:ok, validated} <- Materialization.validate(family_request, opts, :unary),
         {:ok, client} <- runtime_client(opts),
         {:ok, admission_request} <- admission_request(validated, opts, "http.unary"),
         {:ok, %ActiveExecution{} = active} <-
           client.start(admission_request, runtime_client_opts(opts)),
         :ok <- client.subscribe(active.execution_ref, self(), runtime_client_opts(opts)),
         :ok <- demand_with(client, active.execution_ref, 1, opts) do
      await_unary(client, active, validated, opts)
    end
  end

  @impl true
  def stream(family_request, subscriber, opts) when is_pid(subscriber) and is_list(opts) do
    with {:ok, validated} <- Materialization.validate(family_request, opts, :incremental),
         {:ok, client} <- runtime_client(opts),
         {:ok, admission_request} <- admission_request(validated, opts, "http.stream"),
         {:ok, %ActiveExecution{} = active} <-
           client.start(admission_request, runtime_client_opts(opts)) do
      case client.subscribe(active.execution_ref, subscriber, runtime_client_opts(opts)) do
        :ok ->
          {:ok, active}

        {:error, reason} ->
          _ = client.cancel(active.execution_ref, runtime_client_opts(opts))
          {:error, reason}
      end
    end
  end

  def stream(_family_request, _subscriber, _opts) do
    {:error, invalid_error("stream subscriber and options are invalid")}
  end

  @impl true
  def demand(execution_ref, credits, opts) when is_integer(credits) and credits > 0 do
    with {:ok, client} <- runtime_client(opts) do
      demand_with(client, execution_ref, credits, opts)
    end
  end

  def demand(_execution_ref, _credits, _opts) do
    {:error, invalid_error("stream demand must be a positive integer")}
  end

  @impl true
  def status(execution_ref, opts) do
    with {:ok, client} <- runtime_client(opts) do
      client.status(execution_ref, runtime_client_opts(opts))
    end
  end

  @impl true
  def cancel(execution_ref, opts) do
    with {:ok, client} <- runtime_client(opts) do
      client.cancel(execution_ref, runtime_client_opts(opts))
    end
  end

  defp admission_request(validated, opts, operation) do
    try do
      with {:ok, admission} <- admission_options(opts),
           {:ok, authority_ref} <- required_admission(admission, :authority_ref),
           {:ok, sandbox_profile} <- required_admission(admission, :sandbox_profile),
           {:ok, acceptable_attestation} <-
             required_admission(admission, :acceptable_attestation),
           {:ok, placement} <- required_admission(admission, :placement) do
        family_request = validated.family_request

        request =
          AdmissionRequest.new!(
            request_id: admission_value(admission, :request_id),
            lane_id: "http",
            operation: operation,
            payload: Materialization.runtime_payload(validated),
            authority_ref: authority_ref,
            sandbox_profile: sandbox_profile,
            acceptable_attestation: acceptable_attestation,
            placement: placement,
            constraints: admission_value(admission, :constraints, []),
            provenance:
              Provenance.node_admitted(%{
                owner: "pristine",
                admission_ref: admission_value(admission, :admission_ref),
                details: %{
                  "request_ref" => family_request.request_ref,
                  "endpoint_ref" => family_request.endpoint_ref,
                  "header_policy_ref" => family_request.header_policy_ref
                }
              }),
            metadata: %{
              "placement" => "runtime_client_admitted",
              "request_ref" => family_request.request_ref,
              "endpoint_ref" => family_request.endpoint_ref
            }
          )

        {:ok, request}
      end
    rescue
      ArgumentError -> {:error, invalid_error("Runtime Client admission material is invalid")}
    end
  end

  defp admission_options(opts) do
    case Keyword.fetch(opts, :admission) do
      {:ok, admission} when is_map(admission) or is_list(admission) -> {:ok, admission}
      _other -> {:error, invalid_error("Runtime Client admission material is required")}
    end
  end

  defp required_admission(admission, key) do
    case admission_value(admission, key) do
      nil -> {:error, invalid_error("Runtime Client admission material is incomplete")}
      [] -> {:error, invalid_error("Runtime Client admission material is incomplete")}
      value -> {:ok, value}
    end
  end

  defp admission_value(admission, key, default \\ nil)

  defp admission_value(admission, key, default) when is_list(admission),
    do: Keyword.get(admission, key, default)

  defp admission_value(admission, key, default) when is_map(admission),
    do: Map.get(admission, key, Map.get(admission, Atom.to_string(key), default))

  defp runtime_client(opts) do
    case Keyword.fetch(opts, :runtime_client) do
      {:ok, client} when is_atom(client) ->
        callbacks = [
          start: 2,
          subscribe: 3,
          send_input: 3,
          status: 2,
          cancel: 2
        ]

        if Code.ensure_loaded?(client) and
             Enum.all?(callbacks, fn {name, arity} -> function_exported?(client, name, arity) end) do
          {:ok, client}
        else
          {:error, invalid_error("configured Runtime Client is incomplete")}
        end

      _other ->
        {:error, invalid_error("a configured Runtime Client is required")}
    end
  end

  defp runtime_client_opts(opts), do: Keyword.get(opts, :runtime_client_opts, [])

  defp demand_with(client, execution_ref, credits, opts) do
    client.send_input(
      execution_ref,
      %{"control" => "demand", "credits" => credits},
      runtime_client_opts(opts)
    )
  end

  defp await_unary(client, active, validated, opts) do
    timeout = unary_timeout(validated, opts)
    started_at = System.monotonic_time(:millisecond)
    await_unary_event(client, active, opts, timeout, started_at, nil)
  end

  defp await_unary_event(client, active, opts, timeout, started_at, response) do
    remaining = timeout - (System.monotonic_time(:millisecond) - started_at)

    if remaining <= 0 do
      cancel_ambiguous_unary(client, active, opts)
    else
      execution_ref = active.execution_ref.ref

      receive do
        %Event{execution_ref: %ExecutionRef{ref: ^execution_ref}} = event ->
          handle_unary_event(event, client, active, opts, timeout, started_at, response)

        {:execution_plane, %Event{execution_ref: %ExecutionRef{ref: ^execution_ref}} = event} ->
          handle_unary_event(event, client, active, opts, timeout, started_at, response)
      after
        remaining -> cancel_ambiguous_unary(client, active, opts)
      end
    end
  end

  defp handle_unary_event(
         %Event{kind: "output", payload: payload},
         client,
         active,
         opts,
         timeout,
         started_at,
         _response
       ) do
    await_unary_event(
      client,
      active,
      opts,
      timeout,
      started_at,
      response_payload(payload)
    )
  end

  defp handle_unary_event(
         %Event{kind: "receipt", payload: payload},
         _client,
         active,
         _opts,
         _timeout,
         _started_at,
         response
       )
       when not is_nil(response) do
    {:ok,
     ExecutionResult.new!(
       execution_ref: active.execution_ref,
       status: "succeeded",
       output: %{
         "placement" => "runtime_client_admitted",
         "response" => response,
         "receipt" => payload
       },
       provenance: Provenance.node_admitted(owner: "pristine")
     )}
  end

  defp handle_unary_event(
         %Event{kind: "error"},
         _client,
         _active,
         _opts,
         _timeout,
         _started_at,
         _response
       ) do
    {:error,
     Error.new!(
       category: "terminal",
       message: "Runtime Client HTTP request failed",
       retryable: false,
       ambiguous: false
     )}
  end

  defp handle_unary_event(
         _event,
         client,
         active,
         opts,
         timeout,
         started_at,
         response
       ) do
    await_unary_event(client, active, opts, timeout, started_at, response)
  end

  defp response_payload(%{"response" => response}), do: response
  defp response_payload(%{response: response}), do: response
  defp response_payload(payload), do: payload

  defp unary_timeout(%{family_request: family_request}, opts) do
    deadline_timeout =
      max(DateTime.diff(family_request.deadline_at, DateTime.utc_now(), :millisecond), 1)

    case Keyword.get(opts, :await_timeout, deadline_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> min(timeout, deadline_timeout)
      _other -> deadline_timeout
    end
  end

  defp cancel_ambiguous_unary(client, active, opts) do
    _ = client.cancel(active.execution_ref, runtime_client_opts(opts))

    {:error,
     Error.new!(
       category: "timeout",
       message: "Runtime Client HTTP request timed out after admission",
       retryable: false,
       ambiguous: true
     )}
  end

  defp invalid_error(message) do
    Error.new!(
      category: "invalid_request",
      message: message,
      retryable: false,
      ambiguous: false
    )
  end
end
