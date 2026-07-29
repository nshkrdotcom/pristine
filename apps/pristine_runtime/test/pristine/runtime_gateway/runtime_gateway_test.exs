defmodule Pristine.RuntimeGatewayTest do
  use ExUnit.Case, async: false

  alias ExecutionPlane.{ActiveExecution, ExecutionRef}
  alias ExecutionPlane.Admission.Request, as: AdmissionRequest
  alias ExecutionPlane.Family.HTTPGateway
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
         node_id: Keyword.get(opts, :node_id, "effect-node-1"),
         lane_id: "http",
         state: "running",
         started_at: DateTime.utc_now(),
         fence: 1
       )}
    end

    @impl true
    def subscribe(execution_ref, subscriber, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:runtime_subscribe, execution_ref, subscriber})
      Keyword.get(opts, :subscribe_result, :ok)
    end

    @impl true
    def send_input(execution_ref, input, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:runtime_input, execution_ref, input})
      Keyword.get(opts, :input_result, :ok)
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

  defmodule RuntimeUnaryProbe do
    @behaviour ExecutionPlane.Runtime.Client

    @execution_ref "runtime-http-unary-1"
    @receipt_ref "receipt://execution-plane/runtime-http-unary-1/completed"

    @impl true
    def start(request, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:runtime_start, request})

      {:ok,
       ActiveExecution.new!(
         execution_ref: ExecutionRef.new!(ref: @execution_ref),
         session_ref: "runtime-http-unary-session-1",
         admission_decision_ref: "admission-decision-unary-1",
         node_id: "effect-node-unary-1",
         lane_id: "http",
         state: "running",
         started_at: DateTime.utc_now(),
         fence: 1
       )}
    end

    @impl true
    def subscribe(execution_ref, subscriber, opts) do
      Process.put({__MODULE__, execution_ref.ref}, subscriber)
      send(Keyword.fetch!(opts, :test_pid), {:runtime_subscribe, execution_ref, subscriber})
      :ok
    end

    @impl true
    def send_input(execution_ref, %{"control" => "demand"}, opts) do
      subscriber = Process.get({__MODULE__, execution_ref.ref})
      receipt_ref = Keyword.get(opts, :event_receipt_ref, @receipt_ref)

      send(
        subscriber,
        Event.new!(
          execution_ref: execution_ref,
          sequence: 1,
          kind: "output",
          emitted_at: DateTime.utc_now(),
          payload: %{
            "response" => %{
              "status" => 201,
              "headers" => %{"content-type" => "application/json"},
              "body" => ~s({"remote":true})
            }
          }
        )
      )

      send(
        subscriber,
        Event.new!(
          execution_ref: execution_ref,
          sequence: 2,
          kind: "receipt",
          emitted_at: DateTime.utc_now(),
          payload: %{"receipt_ref" => receipt_ref, "state" => "completed"}
        )
      )

      :ok
    end

    @impl true
    def end_input(_execution_ref, _opts), do: :ok

    @impl true
    def status(execution_ref, opts) do
      {:ok,
       Status.new!(
         execution_ref: execution_ref,
         state: "completed",
         sequence: 2,
         input_open: false,
         output_open: false,
         receipt_ref: Keyword.get(opts, :status_receipt_ref, @receipt_ref)
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
      HTTPGateway.behaviour_info(:callbacks) |> MapSet.new()

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

  test "Runtime Client egress changes and HTTPS downgrades fail before admission" do
    opts = runtime_opts(RuntimeClientProbe)

    assert {:error, %Error{category: "invalid_request"}} =
             RuntimeClient.stream(
               family_request("incremental"),
               self(),
               Keyword.put(
                 opts,
                 :request,
                 materialized_request("https://other.example.test/v1/messages")
               )
             )

    assert {:error, %Error{category: "invalid_request"}} =
             RuntimeClient.stream(
               family_request("incremental"),
               self(),
               Keyword.put(
                 opts,
                 :request,
                 materialized_request("http://api.example.test/v1/messages")
               )
             )

    refute_received {:runtime_start, _request}
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
    opts = runtime_opts(RuntimeClientProbe)

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

    assert admission_request.payload["flow_control"] == %{
             "max_demand" => 16,
             "mode" => "credit"
           }

    execution_ref = active.execution_ref

    assert_receive {:runtime_subscribe, ^execution_ref, subscriber}
    assert subscriber == self()

    assert :ok = RuntimeClient.demand(active.execution_ref, 1, opts)

    assert_receive {:runtime_input, ^execution_ref, %{"control" => "demand", "credits" => 1}}

    assert :ok = RuntimeClient.cancel(active.execution_ref, opts)
    assert_receive {:runtime_cancel, ^execution_ref}
    refute_received {:unary_dispatched, _request}
  end

  test "Runtime Client bounds each demand command before dispatch" do
    opts = runtime_opts(RuntimeClientProbe) |> Keyword.put(:max_demand, 2)
    execution_ref = ExecutionRef.new!(ref: "runtime-http-demand-1")

    assert {:error, %Error{category: "backpressure"}} =
             RuntimeClient.demand(execution_ref, 3, opts)

    refute_received {:runtime_input, _execution_ref, _input}

    assert :ok = RuntimeClient.demand(execution_ref, 2, opts)

    assert_receive {:runtime_input, ^execution_ref, %{"control" => "demand", "credits" => 2}}
  end

  test "Runtime Client rejects local execution identity instead of presenting it as remote" do
    opts =
      RuntimeClientProbe
      |> runtime_opts()
      |> Keyword.put(:runtime_client_opts, test_pid: self(), node_id: "local")

    assert {:error, %Error{category: "invalid_request"}} =
             RuntimeClient.stream(family_request("incremental"), self(), opts)

    assert_receive {:runtime_start, %AdmissionRequest{}}
    assert_receive {:runtime_cancel, %ExecutionRef{ref: "runtime-http-1"}}
    refute_received {:runtime_subscribe, _execution_ref, _subscriber}
  end

  test "Runtime Client cancels an admitted execution when subscription fails" do
    opts =
      RuntimeClientProbe
      |> runtime_opts()
      |> Keyword.put(
        :runtime_client_opts,
        test_pid: self(),
        subscribe_result: {:error, :subscription_failed}
      )

    assert {:error, :subscription_failed} =
             RuntimeClient.stream(family_request("incremental"), self(), opts)

    assert_receive {:runtime_subscribe, %ExecutionRef{} = execution_ref, _subscriber}
    assert_receive {:runtime_cancel, ^execution_ref}
  end

  test "Runtime Client unary succeeds only with a terminal status and matching receipt" do
    opts = runtime_opts(RuntimeUnaryProbe)

    assert {:ok, result} = RuntimeClient.unary(family_request("unary"), opts)

    assert result.status == "succeeded"
    assert result.output["placement"] == "runtime_client_admitted"
    assert result.output["response"]["status"] == 201
    assert result.output["receipt"]["state"] == "completed"
    assert result.provenance.kind == "node_admitted"
    assert result.provenance.admission_ref == "admission-decision-unary-1"
    assert result.provenance.details["node_id"] == "effect-node-unary-1"
  end

  test "Runtime Client unary does not claim success for a mismatched receipt" do
    opts =
      RuntimeUnaryProbe
      |> runtime_opts()
      |> Keyword.put(
        :runtime_client_opts,
        test_pid: self(),
        event_receipt_ref: "receipt://execution-plane/wrong"
      )

    assert {:error, %Error{category: "ambiguous", ambiguous: true}} =
             RuntimeClient.unary(family_request("unary"), opts)
  end

  test "Runtime Client unary timeout reaches cancellation and remains ambiguous" do
    opts = runtime_opts(RuntimeClientProbe) |> Keyword.put(:await_timeout, 10)

    assert {:error, %Error{category: "timeout", ambiguous: true}} =
             RuntimeClient.unary(family_request("unary"), opts)

    assert_receive {:runtime_cancel, %ExecutionRef{ref: "runtime-http-1"}}
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

  defp runtime_opts(runtime_client) do
    [
      request: materialized_request("https://api.example.test/v1/messages"),
      context: %Context{},
      endpoint: "https://api.example.test/v1",
      runtime_client: runtime_client,
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
  end
end
