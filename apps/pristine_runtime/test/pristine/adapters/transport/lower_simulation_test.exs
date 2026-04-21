defmodule Pristine.Adapters.Transport.LowerSimulationTest do
  use ExUnit.Case, async: false

  alias Pristine.Adapters.Serializer.JSON
  alias Pristine.Adapters.Transport.LowerSimulation
  alias Pristine.Core.{Context, Request, Response}

  @config_key :transport_simulation_profiles

  setup do
    previous_config = Application.get_env(:pristine, @config_key)

    on_exit(fn ->
      restore_env(previous_config)
    end)

    Application.delete_env(:pristine, @config_key)
    :ok
  end

  test "send/2 dispatches configured lower simulation through Execution Plane without egress" do
    Application.put_env(:pristine, @config_key,
      required?: true,
      profiles: %{
        "github.repos.get" => [
          scenario_ref: "phase5prelim://pristine/github/repos-get",
          status_code: 200,
          headers: %{"content-type" => "application/json"},
          body: ~s({"name":"pristine","private":false})
        ]
      }
    )

    assert {:ok, %Response{} = response} =
             LowerSimulation.send(
               %Request{
                 method: :get,
                 url: "http://127.0.0.1:1/repos/nshkrdotcom/pristine",
                 headers: %{"X-Idempotency-Key" => "idem-pristine-github"},
                 endpoint_id: "github.repos.get",
                 metadata: %{path: "/repos/{owner}/{repo}"}
               },
               context()
             )

    assert response.status == 200
    assert response.headers["content-type"] == "application/json"
    assert response.body == ~s({"name":"pristine","private":false})
    assert response.metadata.lower_simulation?

    assert response.metadata.lower_simulation_scenario_ref ==
             "phase5prelim://pristine/github/repos-get"

    assert [%{"kind" => "lower_simulation_evidence", "evidence" => evidence}] =
             response.metadata.execution_plane_artifacts

    assert evidence["side_effect_policy"] == "deny_external_egress"
    assert evidence["side_effect_result"] == "not_attempted"
    assert evidence["raw_payload_shape"] == ["body", "headers", "status_code"]
  end

  test "execute_request decodes Notion-shaped responses through the normal Pristine pipeline" do
    Application.put_env(:pristine, @config_key,
      required?: true,
      profiles: %{
        "notion.blocks.children.list" => [
          scenario_ref: "phase5prelim://pristine/notion/children",
          body:
            ~s({"object":"list","results":[{"object":"block","id":"block-1","type":"paragraph"}],"has_more":false}),
          headers: %{"content-type" => "application/json"}
        ]
      }
    )

    assert {:ok, data} =
             Pristine.execute_request(
               %{
                 id: "notion.blocks.children.list",
                 method: :get,
                 path: "/v1/blocks/{block_id}/children",
                 path_params: %{block_id: "block-123"},
                 headers: %{"Notion-Version" => "2022-06-28"},
                 response_schema: nil
               },
               context(base_url: "http://127.0.0.1:1")
             )

    assert data["object"] == "list"
    assert [%{"id" => "block-1", "type" => "paragraph"}] = data["results"]
    assert data["has_more"] == false
  end

  test "execute_request decodes GitHub-shaped responses through the normal Pristine pipeline" do
    Application.put_env(:pristine, @config_key,
      profiles: %{
        "github.repos.get" => [
          scenario_ref: "phase5prelim://pristine/github/repo",
          body: ~s({"id":42,"name":"pristine","full_name":"nshkrdotcom/pristine"}),
          headers: %{"content-type" => "application/json"}
        ]
      }
    )

    assert {:ok, data} =
             Pristine.execute_request(
               %{
                 id: "github.repos.get",
                 method: :get,
                 path: "/repos/{owner}/{repo}",
                 path_params: %{owner: "nshkrdotcom", repo: "pristine"},
                 response_schema: nil
               },
               context(base_url: "http://127.0.0.1:1")
             )

    assert data["id"] == 42
    assert data["full_name"] == "nshkrdotcom/pristine"
  end

  test "required missing profile fails before any HTTP egress" do
    Application.put_env(:pristine, @config_key, required?: true, profiles: %{})

    assert {:error, {:pristine_simulation_profile_required, keys}} =
             LowerSimulation.send(
               %Request{
                 method: :get,
                 url: "http://127.0.0.1:1/must-not-egress",
                 endpoint_id: "missing.endpoint"
               },
               context()
             )

    assert "missing.endpoint" in keys
  end

  test "invalid lower simulation descriptor fails closed before HTTP egress" do
    Application.put_env(:pristine, @config_key,
      required?: true,
      profiles: %{
        "invalid.side-effect" => [
          scenario_ref: "phase5prelim://pristine/invalid-side-effect",
          side_effect_policy: "allow_external_egress",
          body: ~s({"ignored":true})
        ]
      }
    )

    assert {:error, {:execution_plane_transport, failure, raw_payload}} =
             LowerSimulation.send(
               %Request{
                 method: :post,
                 url: "http://127.0.0.1:1/must-not-egress",
                 body: ~s({"input":"hashed-only"}),
                 endpoint_id: "invalid.side-effect"
               },
               context()
             )

    assert failure.failure_class == :route_unresolved
    assert raw_payload.side_effect_result == "blocked_before_dispatch"
    assert raw_payload.error =~ "deny_external_egress"
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

  defp restore_env(nil), do: Application.delete_env(:pristine, @config_key)
  defp restore_env(config), do: Application.put_env(:pristine, @config_key, config)
end
