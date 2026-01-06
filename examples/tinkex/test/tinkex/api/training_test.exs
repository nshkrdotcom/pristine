defmodule Tinkex.API.TrainingTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Training
  alias Tinkex.Error

  defmodule MockClient do
    @behaviour Tinkex.HTTPClient

    @impl true
    def post(path, body, opts) do
      send(self(), {:mock_post, path, body, opts})

      case path do
        "/api/v1/forward_backward" ->
          {:ok, %{"request_id" => "fb-future-123"}}

        "/api/v1/optim_step" ->
          {:ok, %{"request_id" => "optim-future-456"}}

        "/api/v1/forward" ->
          {:ok, %{"request_id" => "forward-future-789"}}

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
      {:error, Error.new(:api_connection, "Connection failed")}
    end

    @impl true
    def get(_path, _opts), do: {:error, Error.new(:api_connection, "Connection failed")}
    @impl true
    def delete(_path, _opts), do: {:error, Error.new(:api_connection, "Connection failed")}
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

  describe "forward_backward_future/2" do
    test "sends POST to /api/v1/forward_backward", %{config: config} do
      request = %{model_id: "model-123", inputs: [[1, 2, 3]]}

      {:ok, response} =
        Training.forward_backward_future(request, http_client: MockClient, config: config)

      assert response["request_id"] == "fb-future-123"

      assert_received {:mock_post, "/api/v1/forward_backward", ^request, opts}
      assert opts[:pool_type] == :training
      assert opts[:transform] == [drop_nil?: true]
    end

    test "propagates errors", %{config: config} do
      request = %{model_id: "model-123"}

      assert {:error, %Error{type: :api_connection}} =
               Training.forward_backward_future(request, http_client: ErrorClient, config: config)
    end
  end

  describe "optim_step_future/2" do
    test "sends POST to /api/v1/optim_step", %{config: config} do
      request = %{model_id: "model-123"}

      {:ok, response} =
        Training.optim_step_future(request, http_client: MockClient, config: config)

      assert response["request_id"] == "optim-future-456"

      assert_received {:mock_post, "/api/v1/optim_step", ^request, opts}
      assert opts[:pool_type] == :training
      assert opts[:transform] == [drop_nil?: true]
    end
  end

  describe "forward_future/2" do
    test "sends POST to /api/v1/forward", %{config: config} do
      request = %{model_id: "model-123", inputs: [[1, 2, 3]]}

      {:ok, response} = Training.forward_future(request, http_client: MockClient, config: config)

      assert response["request_id"] == "forward-future-789"

      assert_received {:mock_post, "/api/v1/forward", ^request, opts}
      assert opts[:pool_type] == :training
      assert opts[:transform] == [drop_nil?: true]
    end

    test "allows custom transform options", %{config: config} do
      request = %{model_id: "model-123"}

      {:ok, _response} =
        Training.forward_future(request,
          http_client: MockClient,
          config: config,
          transform: [custom: true]
        )

      assert_received {:mock_post, "/api/v1/forward", ^request, opts}
      # put_new won't override existing transform
      assert opts[:transform] == [custom: true]
    end
  end
end
