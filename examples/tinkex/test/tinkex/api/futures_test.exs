defmodule Tinkex.API.FuturesTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Futures
  alias Tinkex.Error

  defmodule MockClient do
    @behaviour Tinkex.HTTPClient

    @impl true
    def post(path, body, opts) do
      send(self(), {:mock_post, path, body, opts})

      case path do
        "/api/v1/retrieve_future" ->
          {:ok, %{"status" => "completed", "result" => %{"data" => "test"}}}

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

  setup do
    config = %Tinkex.Config{
      base_url: "https://example.com",
      api_key: "tml-test-key",
      timeout: 60_000,
      max_retries: 3
    }

    {:ok, config: config}
  end

  describe "retrieve/2" do
    test "sends POST to /api/v1/retrieve_future", %{config: config} do
      request = %{request_id: "future-abc-123"}

      {:ok, response} = Futures.retrieve(request, http_client: MockClient, config: config)

      assert response["status"] == "completed"
      assert response["result"]["data"] == "test"

      assert_received {:mock_post, "/api/v1/retrieve_future", ^request, opts}
      assert opts[:pool_type] == :futures
      assert opts[:raw_response?] == true
    end

    test "allows overriding raw_response?", %{config: config} do
      request = %{request_id: "future-abc-123"}

      {:ok, _response} =
        Futures.retrieve(request, http_client: MockClient, config: config, raw_response?: false)

      assert_received {:mock_post, "/api/v1/retrieve_future", ^request, opts}
      # Keyword.put_new won't override existing value
      assert opts[:raw_response?] == false
    end
  end
end
