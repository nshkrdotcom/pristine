defmodule Pristine.SDKBoundaryTest do
  use ExUnit.Case, async: true

  alias Pristine.SDK
  alias Pristine.SDK.OAuth2.Provider, as: OAuth2Provider
  alias Pristine.SDK.OpenAPI.{Client, Operation, Runtime}

  test "sdk namespace exposes the public runtime boundary" do
    assert Code.ensure_loaded?(SDK.Context)
    assert function_exported?(SDK.Context, :new, 0)
    assert function_exported?(SDK.Context, :new, 1)
    assert is_map(SDK.Context.new())

    response = SDK.Response.new(status: 429, headers: %{"retry-after" => "1"}, body: "slow down")
    error = SDK.Error.from_response(response)

    assert error.status == 429
    assert SDK.Error.retriable?(error)

    classification =
      SDK.ResultClassification.normalize(
        retry?: true,
        retry_after_ms: 1_000,
        breaker_outcome: :ignore,
        telemetry: %{classification: :rate_limited}
      )

    assert classification.retry? == true
    assert classification.breaker_outcome == :ignore

    request_spec =
      Client.to_request_spec(%{
        args: %{},
        call: {__MODULE__, :request},
        method: :get,
        path_template: "/v1/widgets/{id}",
        path_params: %{"id" => "widget-123"},
        query: %{},
        body: %{},
        form_data: %{}
      })

    assert request_spec.path == "/v1/widgets/{id}"

    partition =
      Operation.partition(
        %{"id" => "widget-123", "cursor" => "cursor-1"},
        %{
          path: [{"id", :id}],
          query: [{"cursor", :cursor}],
          body: %{mode: :none},
          form_data: %{mode: :none}
        }
      )

    assert partition.path_params == %{"id" => "widget-123"}

    assert Operation.render_path("/v1/widgets/{id}", partition.path_params) ==
             "/v1/widgets/widget-123"

    schema =
      Runtime.build_schema([
        %{
          default: nil,
          name: "id",
          nullable: false,
          required: true,
          type: :string
        }
      ])

    assert %Sinter.Schema{} = schema

    provider = OAuth2Provider.new(name: "example")

    assert provider.name == "example"
    assert is_boolean(SDK.OAuth2.available?())
  end

  test "top-level execution helpers stay available through the hardened boundary" do
    context =
      Pristine.foundation_context(
        base_url: "https://api.example.com",
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        rate_limit: false,
        circuit_breaker: false,
        telemetry: false
      )

    assert context.__struct__ == Pristine.SDK.Context.new().__struct__
    assert function_exported?(Pristine, :execute_request, 3)
  end
end
