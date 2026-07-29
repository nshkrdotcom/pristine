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

  alias ExecutionPlane.{
    ActiveExecution,
    Authority,
    ExecutionRef,
    ExecutionResult,
    Placement,
    Provenance,
    Sandbox
  }

  alias ExecutionPlane.Runtime.{Error, Event, Status}
  alias Pristine.RuntimeGateway.Materialization

  @default_max_demand 16

  @impl true
  def unary(family_request, opts) when is_list(opts) do
    with {:ok, validated} <- Materialization.validate(family_request, opts, :unary),
         {:ok, client, client_opts} <- runtime_client(opts),
         {:ok, admission_request} <- admission_request(validated, opts, "http.unary"),
         {:ok, %ActiveExecution{} = active} <-
           start_admitted(client, client_opts, admission_request),
         :ok <- subscribe_or_cancel(client, client_opts, active, self()),
         :ok <- demand_or_cancel(client, client_opts, active, 1) do
      await_unary(client, client_opts, active, validated, opts)
    end
  end

  def unary(_family_request, _opts),
    do: {:error, invalid_error("Runtime Client options are invalid")}

  @impl true
  def stream(family_request, subscriber, opts) when is_pid(subscriber) and is_list(opts) do
    with {:ok, validated} <- Materialization.validate(family_request, opts, :incremental),
         {:ok, _max_demand} <- max_demand(opts),
         {:ok, client, client_opts} <- runtime_client(opts),
         {:ok, admission_request} <- admission_request(validated, opts, "http.stream"),
         {:ok, %ActiveExecution{} = active} <-
           start_admitted(client, client_opts, admission_request),
         :ok <- subscribe_or_cancel(client, client_opts, active, subscriber) do
      {:ok, active}
    end
  end

  def stream(_family_request, _subscriber, _opts) do
    {:error, invalid_error("stream subscriber and options are invalid")}
  end

  @impl true
  def demand(execution_ref, credits, opts)
      when is_integer(credits) and credits > 0 and is_list(opts) do
    with {:ok, max_demand} <- max_demand(opts),
         :ok <- within_demand_window(credits, max_demand),
         {:ok, client, client_opts} <- runtime_client(opts) do
      control_result(
        fn -> client.send_input(execution_ref, demand_input(credits), client_opts) end,
        "Runtime Client demand"
      )
    end
  end

  def demand(_execution_ref, _credits, _opts) do
    {:error, invalid_error("stream demand must be a positive integer")}
  end

  @impl true
  def status(execution_ref, opts) when is_list(opts) do
    with {:ok, client, client_opts} <- runtime_client(opts) do
      status_result(fn -> client.status(execution_ref, client_opts) end)
    end
  end

  def status(_execution_ref, _opts),
    do: {:error, invalid_error("Runtime Client options are invalid")}

  @impl true
  def cancel(execution_ref, opts) when is_list(opts) do
    with {:ok, client, client_opts} <- runtime_client(opts) do
      control_result(
        fn -> client.cancel(execution_ref, client_opts) end,
        "Runtime Client cancellation"
      )
    end
  end

  def cancel(_execution_ref, _opts),
    do: {:error, invalid_error("Runtime Client options are invalid")}

  defp admission_request(validated, opts, operation) do
    with {:ok, admission} <- admission_options(opts),
         {:ok, authority_ref} <- required_admission(admission, :authority_ref),
         {:ok, sandbox_profile} <- required_admission(admission, :sandbox_profile),
         {:ok, acceptable_attestation} <-
           required_admission(admission, :acceptable_attestation),
         {:ok, placement} <- required_admission(admission, :placement),
         {:ok, authority_ref} <- validate_authority(authority_ref),
         {:ok, sandbox_profile} <- validate_sandbox(sandbox_profile),
         {:ok, acceptable_attestation} <-
           validate_attestation(acceptable_attestation),
         {:ok, placement} <- validate_placement(placement) do
      family_request = validated.family_request

      request =
        AdmissionRequest.new!(
          request_id: admission_value(admission, :request_id),
          lane_id: "http",
          operation: operation,
          payload: runtime_payload(validated, opts),
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

  defp admission_options(opts) do
    case Keyword.fetch(opts, :admission) do
      {:ok, admission} when is_map(admission) ->
        {:ok, admission}

      {:ok, admission} when is_list(admission) ->
        if Keyword.keyword?(admission) do
          {:ok, admission}
        else
          {:error, invalid_error("Runtime Client admission material is invalid")}
        end

      _other ->
        {:error, invalid_error("Runtime Client admission material is required")}
    end
  end

  defp required_admission(admission, key) do
    case admission_value(admission, key) do
      nil -> {:error, invalid_error("Runtime Client admission material is incomplete")}
      [] -> {:error, invalid_error("Runtime Client admission material is incomplete")}
      value -> {:ok, value}
    end
  end

  defp validate_authority(value) do
    authority = Authority.Ref.new!(value)

    if present_string?(authority.ref) and present_string?(authority.payload_hash) and
         present_string?(authority.audience) do
      {:ok, authority}
    else
      {:error, invalid_error("Runtime Client authority material is incomplete")}
    end
  end

  defp validate_sandbox(value) do
    sandbox = Sandbox.Profile.new!(value)

    if present_string?(sandbox.profile_ref) and present_string?(sandbox.bundle_hash) and
         not is_nil(sandbox.opaque_bundle) do
      {:ok, sandbox}
    else
      {:error, invalid_error("Runtime Client sandbox material is incomplete")}
    end
  end

  defp validate_attestation(value) do
    attestation = Sandbox.AcceptableAttestation.new!(value)

    if attestation.classes == [] do
      {:error, invalid_error("Runtime Client attestation requirements are incomplete")}
    else
      {:ok, attestation}
    end
  end

  defp validate_placement(value) do
    placement = Placement.Surface.new!(value)

    if placement.surface_kind == "runtime_client" and placement.family == "http" do
      {:ok, placement}
    else
      {:error, invalid_error("Runtime Client HTTP placement is invalid")}
    end
  end

  defp admission_value(admission, key, default \\ nil)

  defp admission_value(admission, key, default) when is_list(admission),
    do: Keyword.get(admission, key, default)

  defp admission_value(admission, key, default) when is_map(admission),
    do: Map.get(admission, key, Map.get(admission, Atom.to_string(key), default))

  defp runtime_client(opts) do
    with {:ok, client} when is_atom(client) <- Keyword.fetch(opts, :runtime_client),
         {:ok, client_opts} <- runtime_client_opts(opts) do
      callbacks = [
        start: 2,
        subscribe: 3,
        send_input: 3,
        end_input: 2,
        status: 2,
        cancel: 2
      ]

      if complete_client?(client, callbacks) do
        {:ok, client, client_opts}
      else
        {:error, invalid_error("configured Runtime Client is incomplete")}
      end
    else
      :error -> {:error, invalid_error("a configured Runtime Client is required")}
      {:ok, _invalid} -> {:error, invalid_error("a configured Runtime Client is required")}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp complete_client?(client, callbacks) do
    Code.ensure_loaded?(client) and
      Enum.all?(callbacks, fn {name, arity} -> function_exported?(client, name, arity) end)
  end

  defp runtime_client_opts(opts) do
    case Keyword.get(opts, :runtime_client_opts, []) do
      client_opts when is_list(client_opts) ->
        if Keyword.keyword?(client_opts) do
          {:ok, client_opts}
        else
          {:error, invalid_error("Runtime Client callback options are invalid")}
        end

      _other ->
        {:error, invalid_error("Runtime Client callback options are invalid")}
    end
  end

  defp start_admitted(client, client_opts, admission_request) do
    case invoke_client(fn -> client.start(admission_request, client_opts) end) do
      {:ok, %ActiveExecution{} = active} ->
        case valid_remote_http_execution(active) do
          {:ok, active} ->
            {:ok, active}

          {:error, %Error{} = error} ->
            cancel_started(client, client_opts, active)
            {:error, error}
        end

      {:ok, _invalid} ->
        {:error, invalid_error("Runtime Client returned invalid execution identity")}

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, unavailable_error("Runtime Client start returned an invalid result")}
    end
  end

  defp valid_remote_http_execution(active) do
    with {:ok, active} <- ActiveExecution.new(active),
         true <- active.lane_id == "http",
         false <- ActiveExecution.terminal?(active),
         false <- local_node_id?(active.node_id) do
      {:ok, active}
    else
      _other ->
        {:error, invalid_error("Runtime Client did not admit a live remote HTTP execution")}
    end
  end

  defp local_node_id?(node_id) when is_binary(node_id) do
    String.downcase(String.trim(node_id)) in ["local", "localhost"]
  end

  defp local_node_id?(_node_id), do: false

  defp subscribe_or_cancel(client, client_opts, active, subscriber) do
    case invoke_client(fn -> client.subscribe(active.execution_ref, subscriber, client_opts) end) do
      :ok ->
        :ok

      {:error, reason} ->
        cancel_started(client, client_opts, active)
        {:error, reason}

      _invalid ->
        cancel_started(client, client_opts, active)
        {:error, unavailable_error("Runtime Client subscription returned an invalid result")}
    end
  end

  defp demand_or_cancel(client, client_opts, active, credits) do
    case invoke_client(fn ->
           client.send_input(active.execution_ref, demand_input(credits), client_opts)
         end) do
      :ok ->
        :ok

      {:error, reason} ->
        cancel_started(client, client_opts, active)
        {:error, reason}

      _invalid ->
        cancel_started(client, client_opts, active)
        {:error, unavailable_error("Runtime Client demand returned an invalid result")}
    end
  end

  defp cancel_started(client, client_opts, active) do
    _ = invoke_client(fn -> client.cancel(active.execution_ref, client_opts) end)
    :ok
  end

  defp demand_input(credits), do: %{"control" => "demand", "credits" => credits}

  defp await_unary(client, client_opts, active, validated, opts) do
    timeout = unary_timeout(validated, opts)
    started_at = System.monotonic_time(:millisecond)
    await_unary_event(client, client_opts, active, timeout, started_at, nil)
  end

  defp await_unary_event(client, client_opts, active, timeout, started_at, response) do
    remaining = timeout - (System.monotonic_time(:millisecond) - started_at)

    if remaining <= 0 do
      cancel_ambiguous_unary(client, client_opts, active)
    else
      execution_ref = active.execution_ref.ref

      receive do
        %Event{execution_ref: %ExecutionRef{ref: ^execution_ref}} = event ->
          handle_unary_event(
            event,
            client,
            client_opts,
            active,
            timeout,
            started_at,
            response
          )

        {:execution_plane, %Event{execution_ref: %ExecutionRef{ref: ^execution_ref}} = event} ->
          handle_unary_event(
            event,
            client,
            client_opts,
            active,
            timeout,
            started_at,
            response
          )
      after
        remaining -> cancel_ambiguous_unary(client, client_opts, active)
      end
    end
  end

  defp handle_unary_event(
         %Event{kind: "output", payload: payload},
         client,
         client_opts,
         active,
         timeout,
         started_at,
         _response
       ) do
    case normalize_response(payload) do
      {:ok, response} ->
        await_unary_event(
          client,
          client_opts,
          active,
          timeout,
          started_at,
          response
        )

      {:error, %Error{} = error} ->
        cancel_started(client, client_opts, active)
        {:error, error}
    end
  end

  defp handle_unary_event(
         %Event{kind: "receipt", payload: payload},
         client,
         client_opts,
         active,
         _timeout,
         _started_at,
         response
       ) do
    complete_unary(client, client_opts, active, payload, response)
  end

  defp handle_unary_event(
         %Event{kind: "error"},
         client,
         client_opts,
         active,
         timeout,
         started_at,
         response
       ) do
    await_unary_event(client, client_opts, active, timeout, started_at, response)
  end

  defp handle_unary_event(
         _event,
         client,
         client_opts,
         active,
         timeout,
         started_at,
         response
       ) do
    await_unary_event(client, client_opts, active, timeout, started_at, response)
  end

  defp normalize_response(payload) when is_map(payload) do
    response = map_value(payload, :response, payload)
    status = is_map(response) && map_value(response, :status)
    headers = is_map(response) && map_value(response, :headers)

    if is_map(response) and is_integer(status) and status in 100..599 and is_map(headers) do
      {:ok,
       %{
         "status" => status,
         "headers" => stringify_map(headers),
         "body" => map_value(response, :body)
       }}
    else
      {:error, unavailable_error("Runtime Client returned an invalid HTTP response")}
    end
  end

  defp normalize_response(_payload),
    do: {:error, unavailable_error("Runtime Client returned an invalid HTTP response")}

  defp complete_unary(client, client_opts, active, receipt, response) do
    with {:ok, %Status{} = status} <-
           status_result(fn -> client.status(active.execution_ref, client_opts) end),
         :ok <- validate_receipt(status, receipt) do
      complete_unary_status(active, status, receipt, response)
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, _reason} ->
        {:error, ambiguous_terminal_error()}
    end
  end

  defp complete_unary_status(active, %Status{state: "completed"}, receipt, response)
       when not is_nil(response) do
    {:ok,
     ExecutionResult.new!(
       execution_ref: active.execution_ref,
       status: "succeeded",
       output: %{
         "placement" => "runtime_client_admitted",
         "response" => response,
         "receipt" => stringify_map(receipt)
       },
       provenance:
         Provenance.node_admitted(
           owner: "pristine",
           admission_ref: active.admission_decision_ref,
           details: %{"node_id" => active.node_id, "lane_id" => active.lane_id}
         )
     )}
  end

  defp complete_unary_status(_active, %Status{state: "completed"}, _receipt, nil),
    do: {:error, unavailable_error("Runtime Client completed without an HTTP response")}

  defp complete_unary_status(_active, %Status{error: %Error{} = error}, _receipt, _response),
    do: {:error, error}

  defp complete_unary_status(_active, %Status{state: "cancelled"}, _receipt, _response) do
    {:error,
     Error.new!(
       category: "cancelled",
       message: "Runtime Client HTTP request was cancelled",
       retryable: false,
       ambiguous: false
     )}
  end

  defp complete_unary_status(_active, %Status{state: "ambiguous"}, _receipt, _response),
    do: {:error, ambiguous_terminal_error()}

  defp complete_unary_status(_active, %Status{state: "failed"}, _receipt, _response),
    do: {:error, terminal_error("Runtime Client HTTP request failed")}

  defp complete_unary_status(_active, _status, _receipt, _response),
    do: {:error, ambiguous_terminal_error()}

  defp validate_receipt(%Status{} = status, receipt) when is_map(receipt) do
    receipt_ref = map_value(receipt, :receipt_ref)
    state = map_value(receipt, :state, map_value(receipt, :status))

    if Status.terminal?(status) and present_string?(receipt_ref) and
         receipt_ref == status.receipt_ref and state == status.state do
      :ok
    else
      {:error, ambiguous_terminal_error()}
    end
  end

  defp validate_receipt(_status, _receipt), do: {:error, ambiguous_terminal_error()}

  defp unary_timeout(%{family_request: family_request}, opts) do
    deadline_timeout =
      max(DateTime.diff(family_request.deadline_at, DateTime.utc_now(), :millisecond), 1)

    case Keyword.get(opts, :await_timeout, deadline_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> min(timeout, deadline_timeout)
      _other -> deadline_timeout
    end
  end

  defp cancel_ambiguous_unary(client, client_opts, active) do
    _ = invoke_client(fn -> client.cancel(active.execution_ref, client_opts) end)

    {:error,
     Error.new!(
       category: "timeout",
       message: "Runtime Client HTTP request timed out after admission",
       retryable: false,
       ambiguous: true
     )}
  end

  defp runtime_payload(validated, opts) do
    payload = Materialization.runtime_payload(validated)

    if validated.family_request.response_mode == "incremental" do
      {:ok, max_demand} = max_demand(opts)
      Map.put(payload, "flow_control", %{"max_demand" => max_demand, "mode" => "credit"})
    else
      payload
    end
  end

  defp max_demand(opts) do
    case Keyword.get(opts, :max_demand, @default_max_demand) do
      max_demand when is_integer(max_demand) and max_demand > 0 ->
        {:ok, max_demand}

      _other ->
        {:error, invalid_error("stream max_demand must be a positive integer")}
    end
  end

  defp within_demand_window(credits, max_demand) when credits <= max_demand, do: :ok

  defp within_demand_window(_credits, _max_demand) do
    {:error,
     Error.new!(
       category: "backpressure",
       message: "HTTP stream demand exceeds the configured credit window",
       retryable: true,
       ambiguous: false
     )}
  end

  defp invoke_client(fun) do
    fun.()
  rescue
    _exception -> {:error, unavailable_error("Runtime Client callback failed")}
  catch
    :exit, _reason -> {:error, unavailable_error("Runtime Client callback exited")}
    _kind, _reason -> {:error, unavailable_error("Runtime Client callback failed")}
  end

  defp control_result(fun, label) do
    case invoke_client(fun) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, unavailable_error("#{label} returned an invalid result")}
    end
  end

  defp status_result(fun) do
    case invoke_client(fun) do
      {:ok, %Status{} = status} ->
        case Status.new(status) do
          {:ok, status} -> {:ok, status}
          {:error, _reason} -> {:error, unavailable_error("Runtime Client status is invalid")}
        end

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, unavailable_error("Runtime Client status returned an invalid result")}
    end
  end

  defp stringify_map(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), nested} end)
  end

  defp map_value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp unavailable_error(message) do
    Error.new!(
      category: "unavailable",
      message: message,
      retryable: true,
      ambiguous: false
    )
  end

  defp ambiguous_terminal_error do
    Error.new!(
      category: "ambiguous",
      message: "Runtime Client HTTP terminal receipt could not be verified",
      retryable: false,
      ambiguous: true
    )
  end

  defp terminal_error(message) do
    Error.new!(
      category: "terminal",
      message: message,
      retryable: false,
      ambiguous: false
    )
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
