defmodule Pristine.RuntimeGatewayTest do
  use ExUnit.Case, async: false

  alias ExecutionPlane.Admission.Request, as: AdmissionRequest
  alias ExecutionPlane.{ActiveExecution, ExecutionRef}
  alias ExecutionPlane.Family.HTTPRequest
  alias ExecutionPlane.Runtime.{Error, Event, Status}
  alias Pristine.Core.{Context, Request, Response, StreamResponse}
  alias Pristine.RuntimeGateway.{Local, RuntimeClient}
  alias Pristine.Streaming.Event, as: SSEEvent

  defmodule CaptureTransport do
    import Kernel, except: [send: 2]

    @behaviour Pristine.Ports.Transport

    @impl true
    def send(request, context) do
      Kernel.send(
        Keyword.fetch!(context.transport_opts, :test_pid),
        {:unary_dispatched, request}
      )

      {:ok, %Response{status: 200, headers: %{"content-type" => "application/json"}, body: "{}"}}
    end
  end

  defmodule DemandProbeStream do
    @behaviour Pristine.Ports.StreamTransport

    @impl true
    def stream(_request, context) do
      test_pid = Keyword.fetch!(context.transport_opts, :test_pid)

      stream =
        Stream.resource(
          fn -> 0 end,
          fn sequence ->
            send(test_pid, {:source_pulled, sequence})

            {[%SSEEvent{id: Integer.to_string(sequence), data: "event-#{sequence}"}],
             sequence + 1}
          end,
          fn _sequence -> send(test_pid, :source_closed) end
        )

      {:ok,
       %StreamResponse{
         stream: stream,
         status: 200,
         headers: %{"content-type" => "text/event-stream"},
         metadata: %{cancel: fn -> send(test_pid, :transport_cancelled) end}
       }}
    end
  end

  defmodule RuntimeClientProbe do
    @behaviour ExecutionPlane.Runtime.Client

    @impl true
    def start(request, opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:runtime_start, request})

      {:ok,
       ActiveExecution.new!(
         execution_ref: ExecutionRef.new!(ref: "runtime-http-1"),
         session_ref: "runtime-http-session-1",
         admission_decision_ref: "admission-decision-1",
         node_id: "effect-node-1",
         lane_id: "http",
         state: "running",
         started_at: DateTime.utc_now(),
         fence: 1
       )}
    end

    @impl true
    def subscribe(execution_ref, subscriber, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:runtime_subscribe, execution_ref, subscriber})
      :ok
    end

    @impl true
    def send_input(execution_ref, input, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:runtime_input, execution_ref, input})
      :ok
    end

    @impl true
    def end_input(_execution_ref, _opts), do: :ok

    @impl true
    def status(execution_ref, _opts) do
      {:ok,
       Status.new!(
         execution_ref: execution_ref,
         state: "running",
         sequence: 1,
         input_open: true,
         output_open: true
       )}
    end

    @impl true
    def cancel(execution_ref, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:runtime_cancel, execution_ref})
      :ok
    end
  end

  test "Pristine gateway preserves the frozen HTTP-family callback surface" do
    pristine_callbacks = Pristine.RuntimeGateway.behaviour_info(:callbacks) |> MapSet.new()

    execution_plane_callbacks =
      ExecutionPlane.Family.HTTPGateway.behaviour_info(:callbacks) |> MapSet.new()

    assert pristine_callbacks == execution_plane_callbacks
  end

  test "local unary execution is endpoint-bound and identified as local" do
    request = materialized_request("https://api.example.test/v1/messages")
    context = %Context{transport: CaptureTransport, transport_opts: [test_pid: self()]}

    assert {:ok, result} =
             Local.unary(
               family_request("unary"),
               request: request,
               context: context,
               endpoint: "https://api.example.test/v1"
             )

    assert_received {:unary_dispatched, dispatched}
    assert dispatched.metadata.timeout <= 5_000
    assert result.output["placement"] == "local_effect"
    assert result.output["response"]["status"] == 200
    assert result.provenance.kind == "direct_lower_lane_owner"
  end

  test "egress host changes and HTTPS downgrades fail before transport dispatch" do
    context = %Context{transport: CaptureTransport, transport_opts: [test_pid: self()]}

    assert {:error, %Error{category: "invalid_request"}} =
             Local.unary(
               family_request("unary"),
               request: materialized_request("https://other.example.test/v1/messages"),
               context: context,
               endpoint: "https://api.example.test/v1"
             )

    assert {:error, %Error{category: "invalid_request"}} =
             Local.unary(
               family_request("unary"),
               request: materialized_request("http://api.example.test/v1/messages"),
               context: context,
               endpoint: "https://api.example.test/v1"
             )

    refute_received {:unary_dispatched, _request}
  end

  test "local incremental execution bounds demand and reaches real transport cancellation" do
    context = %Context{
      stream_transport: DemandProbeStream,
      transport_opts: [test_pid: self()]
    }

    assert {:ok, %ActiveExecution{node_id: "local"} = active} =
             Local.stream(
               family_request("incremental"),
               self(),
               request: materialized_request("https://api.example.test/v1/messages"),
               context: context,
               endpoint: "https://api.example.test/v1",
               max_demand: 2,
               terminal_retention_ms: 5_000
             )

    assert_receive %Event{kind: "started", payload: %{"placement" => "local_effect"}}
    assert_receive {:source_pulled, 0}
    assert_receive %Event{kind: "backpressure"}
    refute_receive {:source_pulled, 1}, 50

    assert {:error, %Error{category: "backpressure"}} =
             Local.demand(active.execution_ref, 3, [])

    assert :ok = Local.demand(active.execution_ref, 1, [])

    assert_receive %Event{
      kind: "output",
      payload: %{"placement" => "local_effect", "event" => %{data: "event-0"}}
    }

    assert_receive {:source_pulled, 1}
    assert_receive %Event{kind: "backpressure"}

    assert :ok = Local.cancel(active.execution_ref, [])
    assert_receive :transport_cancelled
    assert_receive %Event{kind: "receipt", payload: %{"state" => "cancelled"}}

    assert {:ok, %Status{state: "cancelled", receipt_ref: receipt_ref}} =
             Local.status(active.execution_ref, [])

    assert String.starts_with?(receipt_ref, "receipt://pristine/local/")
  end

  test "Runtime Client placement requires admission and never delegates locally" do
    opts = [
      request: materialized_request("https://api.example.test/v1/messages"),
      context: %Context{},
      endpoint: "https://api.example.test/v1",
      runtime_client: RuntimeClientProbe,
      runtime_client_opts: [test_pid: self()],
      admission: %{
        authority_ref: %{
          ref: "authority://tenant-1/http",
          payload_hash: "sha256:authority",
          audience: "execution-plane"
        },
        sandbox_profile: %{
          profile_ref: "sandbox://tenant-1/http",
          bundle_hash: "sha256:sandbox",
          opaque_bundle: %{}
        },
        acceptable_attestation: %{classes: ["beam-peer"], priority_order: ["beam-peer"]},
        placement: %{surface_kind: "runtime_client", family: "http"}
      }
    ]

    assert {:error, %Error{category: "invalid_request"}} =
             RuntimeClient.stream(
               family_request("incremental"),
               self(),
               Keyword.delete(opts, :admission)
             )

    refute_received {:runtime_start, _request}

    assert {:ok, %ActiveExecution{node_id: "effect-node-1"} = active} =
             RuntimeClient.stream(family_request("incremental"), self(), opts)

    assert_receive {:runtime_start, %AdmissionRequest{} = admission_request}
    assert admission_request.operation == "http.stream"
    assert admission_request.provenance.kind == "node_admitted"
    assert admission_request.payload["egress"]["host"] == "api.example.test"

    execution_ref = active.execution_ref

    assert_receive {:runtime_subscribe, ^execution_ref, subscriber}
    assert subscriber == self()

    assert :ok = RuntimeClient.demand(active.execution_ref, 1, opts)

    assert_receive {:runtime_input, ^execution_ref, %{"control" => "demand", "credits" => 1}}

    assert :ok = RuntimeClient.cancel(active.execution_ref, opts)
    assert_receive {:runtime_cancel, ^execution_ref}
    refute_received {:unary_dispatched, _request}
  end

  defp family_request(response_mode) do
    {:ok, request} =
      HTTPRequest.new(%{
        request_ref: "http-request://tenant-1/1",
        endpoint_ref: "endpoint://provider/api",
        method: "POST",
        path: "/v1/messages",
        header_policy_ref: "header-policy://tenant-1/provider",
        response_mode: response_mode,
        idempotency_key: "idem-1",
        deadline_at: DateTime.add(DateTime.utc_now(), 5, :second),
        body_artifact_ref: "artifact://tenant-1/request-body/1"
      })

    request
  end

  defp materialized_request(url) do
    %Request{
      method: "POST",
      url: url,
      headers: %{"X-Idempotency-Key" => "idem-1"},
      body: "{}",
      endpoint_id: "messages.create",
      metadata: %{timeout: 10_000}
    }
  end
end
