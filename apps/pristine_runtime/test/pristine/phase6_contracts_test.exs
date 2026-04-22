defmodule Pristine.Phase6ContractsTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Serializer.JSON
  alias Pristine.Adapters.Transport.LowerSimulation
  alias Pristine.AdapterSelectionPolicy
  alias Pristine.Core.Context
  alias Pristine.LowerSimulationScenario

  test "lower simulation transport declares the Pristine HTTP lower scenario contract" do
    scenario =
      LowerSimulation.lower_simulation_scenario!(
        "lower-scenario://pristine/http/github-repos-get"
      )

    dump = LowerSimulationScenario.dump(scenario)

    assert scenario.contract_version == "ExecutionPlane.LowerSimulationScenario.v1"
    assert scenario.scenario_id == "lower-scenario://pristine/http/github-repos-get"
    assert scenario.owner_repo == "pristine"
    assert scenario.protocol_surface == "http"
    assert scenario.matcher_class == "deterministic_over_input"
    assert scenario.no_egress_assertion["external_egress"] == "deny"
    assert scenario.no_egress_assertion["process_spawn"] == "deny"

    assert scenario.bounded_evidence_projection["contract_version"] ==
             "ExecutionPlane.LowerSimulationEvidence.v1"

    assert scenario.bounded_evidence_projection["raw_payload_persistence"] == "shape_only"
    assert_json_safe(dump)
    assert LowerSimulationScenario.new!(dump) == scenario
  end

  test "Pristine HTTP lower scenarios reject bad owner, unsupported enums, egress, and raw evidence" do
    assert_raise ArgumentError, ~r/owner_repo.*pristine/, fn ->
      LowerSimulationScenario.new!(scenario_attrs(%{owner_repo: "execution_plane"}))
    end

    assert_raise ArgumentError, ~r/protocol_surface.*unsupported/, fn ->
      LowerSimulationScenario.new!(scenario_attrs(%{protocol_surface: "process"}))
    end

    assert_raise ArgumentError, ~r/matcher_class.*unsupported/, fn ->
      LowerSimulationScenario.new!(scenario_attrs(%{matcher_class: "semantic_provider"}))
    end

    assert_raise ArgumentError, ~r/semantic provider policy/i, fn ->
      LowerSimulationScenario.new!(Map.put(scenario_attrs(), :provider_refs, ["notion"]))
    end

    assert_raise ArgumentError, ~r/no_egress_assertion.*external_egress.*deny/, fn ->
      LowerSimulationScenario.new!(
        scenario_attrs(%{no_egress_assertion: %{"external_egress" => "allow"}})
      )
    end

    assert_raise ArgumentError, ~r/raw_payload_persistence.*shape_only/, fn ->
      LowerSimulationScenario.new!(
        scenario_attrs(%{
          bounded_evidence_projection: %{
            "contract_version" => "ExecutionPlane.LowerSimulationEvidence.v1",
            "raw_payload_persistence" => "raw_body"
          }
        })
      )
    end

    assert_raise ArgumentError, ~r/ExecutionOutcome.v1.raw_payload.*must not be narrowed/, fn ->
      LowerSimulationScenario.new!(
        scenario_attrs(%{
          bounded_evidence_projection: %{
            "contract_version" => "ExecutionPlane.LowerSimulationEvidence.v1",
            "target_contract" => "ExecutionOutcome.v1.raw_payload",
            "raw_payload_persistence" => "shape_only"
          }
        })
      )
    end
  end

  test "lower simulation transport declares app-config adapter selection only" do
    policy = LowerSimulation.adapter_selection_policy()
    dump = AdapterSelectionPolicy.dump(policy)

    assert policy.contract_version == "ExecutionPlane.AdapterSelectionPolicy.v1"
    assert policy.owner_repo == "pristine"
    assert policy.selection_surface == "application_config"
    assert policy.config_key == "pristine.transport_simulation_profiles"
    assert policy.default_value_when_unset == "normal_http_transport"
    assert policy.fail_closed_action_when_misconfigured == "reject_required_or_invalid_profile"
    assert_json_safe(dump)
    assert AdapterSelectionPolicy.new!(dump) == policy

    assert_raise ArgumentError, ~r/public simulation selector/i, fn ->
      AdapterSelectionPolicy.new!(Map.put(adapter_policy_attrs(), :simulation, "service_mode"))
    end

    assert_raise ArgumentError, ~r/config_key.*public simulation selector/i, fn ->
      AdapterSelectionPolicy.new!(adapter_policy_attrs(%{config_key: "request.simulation"}))
    end
  end

  test "public simulation request selectors are rejected before transport selection" do
    request = %{
      id: "github.repos.get",
      method: :get,
      path: "/repos/{owner}/{repo}",
      path_params: %{owner: "nshkrdotcom", repo: "pristine"},
      response_schema: nil
    }

    assert {:error, {:public_simulation_selector_forbidden, :pristine}} =
             Pristine.execute_request(request, context(), simulation: :service_mode)
  end

  test "transport config simulation selectors are rejected before profile lookup" do
    assert {:error, {:public_simulation_selector_forbidden, :pristine}} =
             LowerSimulation.send(
               %Pristine.Core.Request{
                 method: :get,
                 url: "http://127.0.0.1:1/must-not-egress",
                 endpoint_id: "github.repos.get"
               },
               context(transport_opts: [simulation: :service_mode])
             )
  end

  defp scenario_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        scenario_id: "lower-scenario://pristine/http/github-repos-get",
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
      },
      overrides
    )
  end

  defp adapter_policy_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        selection_surface: "application_config",
        owner_repo: "pristine",
        config_key: "pristine.transport_simulation_profiles",
        default_value_when_unset: "normal_http_transport",
        fail_closed_action_when_misconfigured: "reject_required_or_invalid_profile"
      },
      overrides
    )
  end

  defp context(opts \\ []) do
    opts
    |> Keyword.put_new(:base_url, "http://127.0.0.1:1")
    |> Keyword.put(:transport, LowerSimulation)
    |> Keyword.put(:serializer, JSON)
    |> Keyword.put(:retry, Pristine.Adapters.Retry.Noop)
    |> Keyword.put(:rate_limiter, Pristine.Adapters.RateLimit.Noop)
    |> Keyword.put(:circuit_breaker, Pristine.Adapters.CircuitBreaker.Noop)
    |> Keyword.put(:telemetry, Pristine.Adapters.Telemetry.Noop)
    |> Context.new()
  end

  defp assert_json_safe(value) when is_binary(value) or is_boolean(value) or is_nil(value),
    do: :ok

  defp assert_json_safe(value) when is_integer(value) or is_float(value), do: :ok

  defp assert_json_safe(value) when is_list(value), do: Enum.each(value, &assert_json_safe/1)

  defp assert_json_safe(value) when is_map(value) do
    assert Enum.all?(Map.keys(value), &is_binary/1)
    Enum.each(value, fn {_key, nested} -> assert_json_safe(nested) end)
  end
end
