defmodule Pristine.Adapters.Transport.LowerSimulation do
  @moduledoc """
  Configured unary HTTP simulation transport backed by Execution Plane.

  This adapter is selected through normal Pristine transport configuration. It
  reads scenario profiles from application or context transport config, injects
  a lower-simulation route descriptor, and lets Execution Plane enforce the
  no-egress contract.
  """

  @behaviour Pristine.Ports.Transport

  alias ExecutionPlane.HTTP, as: ExecutionPlaneHTTP
  alias Pristine.{AdapterSelectionPolicy, LowerSimulationScenario}
  alias Pristine.Core.{Context, Request, Response}

  @app :pristine
  @config_key :transport_simulation_profiles
  @default_side_effect_policy "deny_external_egress"
  @default_no_egress_policy %{
    "policy_ref" => "no-egress-policy://execution-plane/lower/v1",
    "owner_repo" => "execution_plane",
    "mode" => "deny",
    "enforcement_boundary" => "lower_runtime",
    "denied_surfaces" => %{
      "external_egress" => "deny",
      "process_spawn" => "deny",
      "unregistered_provider_route" => "deny",
      "raw_external_saas_write_path" => "deny"
    },
    "required_negative_evidence" => [
      "attempted_unregistered_provider_route",
      "attempted_raw_external_saas_write_path"
    ]
  }
  @missing {__MODULE__, :missing}

  @doc """
  Declares the Phase 6 adapter selection policy for Pristine HTTP simulation.
  """
  @spec adapter_selection_policy() :: AdapterSelectionPolicy.t()
  def adapter_selection_policy do
    AdapterSelectionPolicy.new!(%{
      selection_surface: "application_config",
      owner_repo: "pristine",
      config_key: "pristine.transport_simulation_profiles",
      default_value_when_unset: "normal_http_transport",
      fail_closed_action_when_misconfigured: "reject_required_or_invalid_profile"
    })
  end

  @doc """
  Builds the owner-local Phase 6 lower scenario declaration for an HTTP profile.
  """
  @spec lower_simulation_scenario!(String.t(), map() | keyword()) :: LowerSimulationScenario.t()
  def lower_simulation_scenario!(scenario_ref, overrides \\ []) when is_binary(scenario_ref) do
    overrides = normalize_overrides!(overrides)

    %{
      scenario_id: scenario_ref,
      version: "1.0.0",
      owner_repo: "pristine",
      route_kind: "http_request",
      protocol_surface: "http",
      matcher_class: "deterministic_over_input",
      status_or_exit_or_response_or_stream_or_chunk_or_fault_shape: %{
        "status_code" => "configured",
        "headers" => "configured",
        "body" => "configured"
      },
      no_egress_assertion: %{
        "external_egress" => "deny",
        "process_spawn" => "deny",
        "side_effect_result" => "not_attempted"
      },
      bounded_evidence_projection: %{
        "contract_version" => "ExecutionPlane.LowerSimulationEvidence.v1",
        "raw_payload_persistence" => "shape_only",
        "fingerprints" => ["input", "response_shape"]
      },
      input_fingerprint_ref: "fingerprint://pristine/http/lower-simulation/input",
      cleanup_behavior: %{
        "runtime_artifacts" => "delete",
        "durable_payload" => "deny_raw"
      }
    }
    |> Map.merge(overrides)
    |> LowerSimulationScenario.new!()
  end

  @impl true
  def send(%Request{} = request, %Context{} = context) do
    with :ok <- reject_public_simulation_selector(context.transport_opts),
         {:ok, method} <- normalize_method(request.method),
         {:ok, profile} <- resolve_profile(request, context),
         {:ok, descriptor} <- lower_simulation_descriptor(request, profile) do
      request
      |> build_execution_request(method)
      |> ExecutionPlaneHTTP.unary(
        lineage: execution_lineage(request),
        route: %{resolved_target: %{"lower_simulation" => descriptor}}
      )
      |> normalize_execution_result(descriptor)
    end
  end

  defp resolve_profile(%Request{} = request, %Context{} = context) do
    config = merged_config(context)

    with :ok <- reject_public_simulation_selector(config),
         {:ok, required?} <- required?(config),
         {:ok, profile} <- configured_profile(config, request) do
      case profile do
        nil when required? ->
          {:error, {:pristine_simulation_profile_required, profile_keys(request)}}

        nil ->
          {:error, {:pristine_simulation_profile_not_configured, profile_keys(request)}}

        profile ->
          {:ok, profile}
      end
    end
  end

  defp merged_config(%Context{} = context) do
    app_config = Application.get_env(@app, @config_key)
    context_config = context.transport_opts

    merge_config(app_config, context_config)
  end

  defp merge_config(nil, context_config), do: context_config
  defp merge_config(app_config, nil), do: app_config
  defp merge_config(app_config, []), do: app_config

  defp merge_config(app_config, context_config)
       when (is_list(app_config) or is_map(app_config)) and
              (is_list(context_config) or is_map(context_config)) do
    app_profiles = config_value(app_config, :profiles, %{})
    context_profiles = config_value(context_config, :profiles, %{})

    app_config
    |> to_map()
    |> Map.merge(to_map(context_config))
    |> Map.put(:profiles, Map.merge(to_map(app_profiles), to_map(context_profiles)))
  end

  defp merge_config(_app_config, context_config), do: context_config

  defp normalize_overrides!(overrides) when is_map(overrides), do: overrides

  defp normalize_overrides!(overrides) when is_list(overrides) do
    if Keyword.keyword?(overrides) do
      Map.new(overrides)
    else
      raise ArgumentError, "expected keyword overrides, got: #{inspect(overrides)}"
    end
  end

  defp normalize_overrides!(overrides) do
    raise ArgumentError, "expected map or keyword overrides, got: #{inspect(overrides)}"
  end

  defp reject_public_simulation_selector(values) when is_list(values) do
    if Enum.any?(values, &public_simulation_entry?/1) do
      {:error, {:public_simulation_selector_forbidden, :pristine}}
    else
      :ok
    end
  end

  defp reject_public_simulation_selector(values) when is_map(values) do
    if Map.has_key?(values, :simulation) or Map.has_key?(values, "simulation") do
      {:error, {:public_simulation_selector_forbidden, :pristine}}
    else
      :ok
    end
  end

  defp reject_public_simulation_selector(_values), do: :ok

  defp public_simulation_entry?({key, _value}), do: key in [:simulation, "simulation"]
  defp public_simulation_entry?(_entry), do: false

  defp required?(config) do
    case config_value(config, :required?, false) do
      value when is_boolean(value) -> {:ok, value}
      other -> {:error, {:invalid_pristine_simulation_required?, other}}
    end
  end

  defp configured_profile(config, %Request{} = request) do
    profiles = config_value(config, :profiles, %{})

    profile =
      request
      |> profile_keys()
      |> Enum.find_value(fn key -> profile_lookup(profiles, key) end)

    case profile do
      nil ->
        {:ok, nil}

      false ->
        {:ok, nil}

      profile when is_list(profile) or is_map(profile) ->
        if config_value(profile, :enabled?, true) == false do
          {:ok, nil}
        else
          {:ok, profile}
        end

      other ->
        {:error, {:invalid_pristine_simulation_profile, other}}
    end
  end

  defp profile_lookup(profiles, key) do
    case config_value(profiles, key, @missing) do
      @missing -> nil
      profile -> profile
    end
  end

  defp profile_keys(%Request{} = request) do
    endpoint = Map.get(request.metadata, :endpoint)

    [
      request.endpoint_id,
      endpoint && endpoint.id,
      Map.get(request.metadata, :path),
      request.url,
      :default
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&normalize_key/1)
  end

  defp lower_simulation_descriptor(%Request{} = request, profile) do
    with {:ok, scenario_ref} <- required_string(profile, :scenario_ref),
         {:ok, raw_payload} <- raw_payload(profile),
         {:ok, outcome_status} <- outcome_status(profile),
         {:ok, metrics} <- metrics(profile),
         {:ok, side_effect_policy} <- side_effect_policy(profile),
         {:ok, no_egress_policy} <- no_egress_policy(profile),
         {:ok, failure} <- failure(profile) do
      descriptor =
        %{
          "scenario_ref" => scenario_ref,
          "status" => outcome_status,
          "raw_payload" => raw_payload,
          "metrics" => metrics,
          "side_effect_policy" => side_effect_policy,
          "no_egress_policy" => no_egress_policy
        }
        |> maybe_put("failure", failure)

      {:ok, descriptor}
    else
      {:error, reason} ->
        {:error, {:invalid_pristine_simulation_profile, request.endpoint_id, reason}}
    end
  end

  defp raw_payload(profile) do
    case profile_value(profile, :raw_payload, @missing) do
      %{} = raw_payload ->
        normalize_raw_payload(raw_payload)

      @missing ->
        with {:ok, status_code} <- status_code(profile),
             {:ok, headers} <- headers(profile),
             {:ok, body} <- required_string(profile, :body) do
          {:ok,
           %{
             "status_code" => status_code,
             "headers" => headers,
             "body" => body
           }}
        end

      other ->
        {:error, {:invalid_raw_payload, other}}
    end
  end

  defp normalize_raw_payload(raw_payload) do
    raw_payload = stringify_keys(raw_payload)

    with {:ok, status_code} <- status_code(raw_payload),
         {:ok, headers} <- headers(raw_payload),
         {:ok, body} <- raw_payload_body(raw_payload) do
      {:ok, %{"status_code" => status_code, "headers" => headers, "body" => body}}
    end
  end

  defp status_code(profile) do
    case profile_value(profile, :status_code, profile_value(profile, :http_status, 200)) do
      status when is_integer(status) and status >= 100 and status <= 599 -> {:ok, status}
      other -> {:error, {:invalid_status_code, other}}
    end
  end

  defp headers(profile) do
    case profile_value(profile, :headers, %{}) do
      headers when is_map(headers) ->
        {:ok, Map.new(headers, fn {key, value} -> {to_string(key), to_string(value)} end)}

      headers when is_list(headers) ->
        if Keyword.keyword?(headers) do
          {:ok, Map.new(headers, fn {key, value} -> {to_string(key), to_string(value)} end)}
        else
          {:error, {:invalid_headers, headers}}
        end

      other ->
        {:error, {:invalid_headers, other}}
    end
  end

  defp raw_payload_body(raw_payload) do
    case profile_value(raw_payload, :body, @missing) do
      body when is_binary(body) -> {:ok, body}
      @missing -> {:error, {:missing_required_option, :body}}
      other -> {:error, {:invalid_body, other}}
    end
  end

  defp outcome_status(profile) do
    case profile_value(
           profile,
           :outcome_status,
           profile_value(profile, :simulation_status, "succeeded")
         ) do
      value when value in ["succeeded", "failed"] -> {:ok, value}
      other -> {:error, {:invalid_outcome_status, other}}
    end
  end

  defp metrics(profile) do
    case profile_value(profile, :metrics, %{"duration_ms" => 0}) do
      metrics when is_map(metrics) -> {:ok, stringify_keys(metrics)}
      other -> {:error, {:invalid_metrics, other}}
    end
  end

  defp side_effect_policy(profile) do
    case profile_value(profile, :side_effect_policy, @default_side_effect_policy) do
      value when is_binary(value) -> {:ok, value}
      other -> {:error, {:invalid_side_effect_policy, other}}
    end
  end

  defp no_egress_policy(profile) do
    case profile_value(profile, :no_egress_policy, @default_no_egress_policy) do
      policy when is_map(policy) -> {:ok, stringify_keys(policy)}
      other -> {:error, {:invalid_no_egress_policy, other}}
    end
  end

  defp failure(profile) do
    case profile_value(profile, :failure, nil) do
      nil -> {:ok, nil}
      failure when is_map(failure) -> {:ok, stringify_keys(failure)}
      other -> {:error, {:invalid_failure, other}}
    end
  end

  defp required_string(profile, key) do
    case profile_value(profile, key, @missing) do
      value when is_binary(value) and value != "" -> {:ok, value}
      @missing -> {:error, {:missing_required_option, key}}
      other -> {:error, {:invalid_string_option, key, other}}
    end
  end

  defp build_execution_request(%Request{} = request, method) do
    %{
      url: request.url,
      method: method,
      headers: request.headers,
      body: request.body,
      timeout_ms: Map.get(request.metadata, :timeout)
    }
  end

  defp normalize_execution_result({:ok, result}, descriptor) do
    raw_payload = result.outcome.raw_payload

    {:ok,
     %Response{
       status: payload_value(raw_payload, :status_code),
       headers: payload_value(raw_payload, :headers) || %{},
       body: payload_value(raw_payload, :body),
       metadata: simulation_metadata(result, descriptor)
     }}
  end

  defp normalize_execution_result({:error, result}, _descriptor) do
    {:error, {:execution_plane_transport, result.outcome.failure, result.outcome.raw_payload}}
  end

  defp simulation_metadata(result, descriptor) do
    %{
      lower_simulation?: true,
      lower_simulation_scenario_ref: descriptor["scenario_ref"],
      execution_plane_outcome_status: result.outcome.status,
      execution_plane_family: result.outcome.family,
      execution_plane_artifacts: result.outcome.artifacts
    }
  end

  defp execution_lineage(%Request{} = request) do
    %{}
    |> maybe_put(
      :idempotency_key,
      idempotency_key(request.headers) || generated_idempotency_key()
    )
    |> maybe_put(:request_id, request.endpoint_id)
  end

  defp generated_idempotency_key do
    token = System.unique_integer([:positive, :monotonic])
    "pristine-http-lower-#{token}"
  end

  defp normalize_method(method) when is_atom(method), do: {:ok, method}

  defp normalize_method(method) when is_binary(method) do
    case String.downcase(method) do
      "get" -> {:ok, :get}
      "post" -> {:ok, :post}
      "put" -> {:ok, :put}
      "patch" -> {:ok, :patch}
      "delete" -> {:ok, :delete}
      "head" -> {:ok, :head}
      "options" -> {:ok, :options}
      _ -> {:error, :invalid_method}
    end
  end

  defp normalize_method(_method), do: {:error, :invalid_method}

  defp idempotency_key(headers) when is_map(headers) do
    Enum.find_value(headers, fn {key, value} ->
      if String.contains?(String.downcase(to_string(key)), "idempotency-key") do
        to_string(value)
      end
    end)
  end

  defp idempotency_key(_headers), do: nil

  defp payload_value(payload, key) when is_map(payload) do
    Map.get(payload, key, Map.get(payload, to_string(key)))
  end

  defp profile_value(profile, key, default) do
    config_value(profile, key, default)
  end

  defp config_value(nil, _key, default), do: default

  defp config_value(config, key, default) when is_list(config) do
    case Enum.find(config, &matching_key?(&1, key)) do
      {_key, value} -> value
      nil -> default
    end
  end

  defp config_value(config, key, default) when is_map(config) do
    Map.get(config, key, Map.get(config, to_string(key), default))
  end

  defp config_value(_config, _key, default), do: default

  defp matching_key?({entry_key, _value}, key) do
    normalize_key(entry_key) == normalize_key(key)
  end

  defp matching_key?(_entry, _key), do: false

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp to_map(nil), do: %{}

  defp to_map(config) when is_list(config) do
    if Keyword.keyword?(config) do
      Map.new(config)
    else
      Map.new(config, fn {key, value} -> {key, value} end)
    end
  end

  defp to_map(config) when is_map(config), do: config
  defp to_map(_config), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
