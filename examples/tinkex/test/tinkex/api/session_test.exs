defmodule Tinkex.API.SessionTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Session
  alias Tinkex.Error

  defmodule MockClient do
    @behaviour Tinkex.HTTPClient

    @impl true
    def post(path, body, opts) do
      send(self(), {:mock_post, path, body, opts})

      case path do
        "/api/v1/create_session" ->
          {:ok,
           %{
             "session_id" => "test-session-123",
             "info_message" => "Session created successfully"
           }}

        "/api/v1/session_heartbeat" ->
          {:ok, %{"status" => "ok"}}

        _ ->
          {:error, Error.new(:api_status, "Not found", status: 404)}
      end
    end

    @impl true
    def get(_path, _opts), do: {:error, Error.new(:api_status, "Method not allowed", status: 405)}

    @impl true
    def delete(_path, _opts),
      do: {:error, Error.new(:api_status, "Method not allowed", status: 405)}
  end

  defmodule ErrorClient do
    @behaviour Tinkex.HTTPClient

    @impl true
    def post(_path, _body, _opts) do
      {:error, Error.new(:api_connection, "Connection refused")}
    end

    @impl true
    def get(_path, _opts), do: {:error, Error.new(:api_connection, "Connection refused")}
    @impl true
    def delete(_path, _opts), do: {:error, Error.new(:api_connection, "Connection refused")}
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

  describe "create/2" do
    test "sends POST to /api/v1/create_session", %{config: config} do
      request = %{model_id: "test-model", config: %{}}

      {:ok, response} = Session.create(request, http_client: MockClient, config: config)

      assert response["session_id"] == "test-session-123"

      assert_received {:mock_post, "/api/v1/create_session", ^request, opts}
      assert opts[:pool_type] == :session
    end

    test "returns error on failure", %{config: config} do
      request = %{model_id: "test-model"}

      assert {:error, %Error{type: :api_connection}} =
               Session.create(request, http_client: ErrorClient, config: config)
    end
  end

  describe "create_typed/2" do
    test "returns typed CreateSessionResponse", %{config: config} do
      request = %{model_id: "test-model", config: %{}}

      {:ok, response} = Session.create_typed(request, http_client: MockClient, config: config)

      assert %Tinkex.Types.CreateSessionResponse{} = response
      assert response.session_id == "test-session-123"
      assert response.info_message == "Session created successfully"
    end

    test "propagates errors", %{config: config} do
      request = %{model_id: "test-model"}

      assert {:error, %Error{}} =
               Session.create_typed(request, http_client: ErrorClient, config: config)
    end
  end

  describe "heartbeat/2" do
    test "sends POST to /api/v1/session_heartbeat with custom timeout", %{config: config} do
      request = %{session_id: "test-session-123"}

      {:ok, response} = Session.heartbeat(request, http_client: MockClient, config: config)

      assert response["status"] == "ok"

      assert_received {:mock_post, "/api/v1/session_heartbeat", ^request, opts}
      assert opts[:pool_type] == :session
      assert opts[:timeout] == 10_000
      assert opts[:max_retries] == 0
    end
  end
end
