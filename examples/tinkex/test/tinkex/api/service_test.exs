defmodule Tinkex.API.ServiceTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Service
  alias Tinkex.Error

  defmodule MockClient do
    @behaviour Tinkex.HTTPClient

    @impl true
    def post(path, body, opts) do
      send(self(), {:mock_post, path, body, opts})

      case path do
        "/api/v1/create_model" ->
          {:ok, %{"model_id" => "model-123", "status" => "created"}}

        "/api/v1/create_sampling_session" ->
          {:ok, %{"session_id" => "sampling-session-456"}}

        _ ->
          {:error, Error.new(:api_status, "Not found", status: 404)}
      end
    end

    @impl true
    def get(path, opts) do
      send(self(), {:mock_get, path, opts})

      case path do
        "/api/v1/get_server_capabilities" ->
          {:ok,
           %{
             "supported_models" => [
               %{"name" => "model-a", "description" => "Test model A"},
               %{"name" => "model-b", "description" => "Test model B"}
             ]
           }}

        "/api/v1/healthz" ->
          {:ok, %{"status" => "healthy"}}

        _ ->
          {:error, Error.new(:api_status, "Not found", status: 404)}
      end
    end

    @impl true
    def delete(_path, _opts),
      do: {:error, Error.new(:api_status, "Method not allowed", status: 405)}
  end

  setup do
    config = %Tinkex.Config{
      base_url: "https://example.com",
      api_key: "tml-test-key",
      timeout: 60_000,
      max_retries: 3
    }

    {:ok, config: config}
  end

  describe "get_server_capabilities/1" do
    test "sends GET to /api/v1/get_server_capabilities", %{config: config} do
      {:ok, response} = Service.get_server_capabilities(http_client: MockClient, config: config)

      assert %Tinkex.Types.GetServerCapabilitiesResponse{} = response
      assert length(response.supported_models) == 2

      assert_received {:mock_get, "/api/v1/get_server_capabilities", opts}
      assert opts[:pool_type] == :session
    end
  end

  describe "health_check/1" do
    test "sends GET to /api/v1/healthz", %{config: config} do
      {:ok, response} = Service.health_check(http_client: MockClient, config: config)

      assert %Tinkex.Types.HealthResponse{} = response
      assert response.status == "healthy"

      assert_received {:mock_get, "/api/v1/healthz", opts}
      assert opts[:pool_type] == :session
    end
  end

  describe "create_model/2" do
    test "sends POST to /api/v1/create_model", %{config: config} do
      request = %{model_name: "test-model", config: %{}}

      {:ok, response} = Service.create_model(request, http_client: MockClient, config: config)

      assert response["model_id"] == "model-123"

      assert_received {:mock_post, "/api/v1/create_model", ^request, opts}
      assert opts[:pool_type] == :session
    end
  end

  describe "create_sampling_session/2" do
    test "sends POST to /api/v1/create_sampling_session", %{config: config} do
      request = %{model_id: "model-123"}

      {:ok, response} =
        Service.create_sampling_session(request, http_client: MockClient, config: config)

      assert response["session_id"] == "sampling-session-456"

      assert_received {:mock_post, "/api/v1/create_sampling_session", ^request, opts}
      assert opts[:pool_type] == :session
    end
  end
end
