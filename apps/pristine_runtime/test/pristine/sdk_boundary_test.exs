defmodule Pristine.SDKBoundaryTest do
  use ExUnit.Case, async: true

  alias Pristine.SDK
  alias Pristine.SDK.OAuth2.Provider, as: OAuth2Provider
  alias Pristine.SDK.OpenAPI.{Client, Operation, Runtime}

  @sdk_source_glob Path.expand("../../lib/pristine/sdk/**/*.ex", __DIR__)
  @oauth_backend_port_path Path.expand("../../lib/pristine/ports/oauth_backend.ex", __DIR__)
  @oauth_backend_path Path.expand("../../lib/pristine/oauth2/backend.ex", __DIR__)
  @interactive_path Path.expand("../../lib/pristine/oauth2/interactive.ex", __DIR__)

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

  test "sdk oauth provider construction stays manifest-free" do
    violations =
      @sdk_source_glob
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        [
          {"Pristine.Manifest", "Pristine.Manifest"},
          {"from_manifest(", "from_manifest/2"},
          {"from_manifest!(", "from_manifest!/2"}
        ]
        |> Enum.flat_map(fn {pattern, label} ->
          if String.contains?(source, pattern) do
            ["#{path}: #{label}"]
          else
            []
          end
        end)
      end)

    assert violations == []
    assert Code.ensure_loaded?(OAuth2Provider)
    assert function_exported?(OAuth2Provider, :from_security_scheme, 3)
    assert function_exported?(OAuth2Provider, :from_security_scheme!, 3)
    refute function_exported?(OAuth2Provider, :from_manifest, 2)
    refute function_exported?(OAuth2Provider, :from_manifest!, 2)
  end

  test "oauth control-plane routes through a real pristine-native backend port" do
    backend_port = File.read!(@oauth_backend_port_path)
    backend = File.read!(@oauth_backend_path)

    assert backend_port =~ "defmodule Pristine.Ports.OAuthBackend"
    assert backend_port =~ "@callback authorization_url"
    assert backend_port =~ "@callback build_request"
    assert backend_port =~ "@callback normalize_token_response"

    assert backend =~ "Pristine.Ports.OAuthBackend"
    refute backend =~ "new_client"
    refute backend =~ "prepare_token_request"
    refute backend =~ "access_token"
  end

  test "interactive oauth defaults through explicit browser and callback adapter seams" do
    interactive = File.read!(@interactive_path)

    assert interactive =~ "Pristine.Adapters.OAuthBrowser.SystemCmd"
    assert interactive =~ "Pristine.Adapters.OAuthCallbackListener.Bandit"
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
    refute function_exported?(Pristine, :load_manifest, 1)
    refute function_exported?(Pristine, :load_manifest_file, 1)
    refute function_exported?(Pristine, :execute, 5)
    refute function_exported?(Pristine, :execute_endpoint, 4)
  end
end
