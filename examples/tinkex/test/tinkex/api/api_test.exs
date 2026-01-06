defmodule Tinkex.APITest do
  use ExUnit.Case, async: true

  alias Tinkex.API
  alias Tinkex.Error

  defmodule MockClient do
    @behaviour Tinkex.HTTPClient

    @impl true
    def post(path, body, opts) do
      send(self(), {:mock_post, path, body, opts})
      {:ok, %{"mocked" => true, "path" => path}}
    end

    @impl true
    def get(path, opts) do
      send(self(), {:mock_get, path, opts})
      {:ok, %{"mocked" => true, "path" => path}}
    end

    @impl true
    def delete(path, opts) do
      send(self(), {:mock_delete, path, opts})
      {:ok, %{"mocked" => true, "path" => path}}
    end
  end

  defmodule ErrorClient do
    @behaviour Tinkex.HTTPClient

    @impl true
    def post(_path, _body, _opts) do
      {:error, Error.new(:api_connection, "Connection failed")}
    end

    @impl true
    def get(_path, _opts) do
      {:error, Error.new(:api_connection, "Connection failed")}
    end

    @impl true
    def delete(_path, _opts) do
      {:error, Error.new(:api_connection, "Connection failed")}
    end
  end

  describe "client_module/1" do
    test "returns http_client from opts when provided" do
      assert API.client_module(http_client: MockClient) == MockClient
    end

    test "returns http_client from config when provided" do
      config = %Tinkex.Config{
        base_url: "https://example.com",
        api_key: "tml-test-key",
        timeout: 60_000,
        max_retries: 3,
        http_client: MockClient
      }

      assert API.client_module(config: config) == MockClient
    end

    test "opts http_client takes precedence over config" do
      config = %Tinkex.Config{
        base_url: "https://example.com",
        api_key: "tml-test-key",
        timeout: 60_000,
        max_retries: 3,
        http_client: ErrorClient
      }

      assert API.client_module(http_client: MockClient, config: config) == MockClient
    end

    test "returns Tinkex.API when no custom client specified" do
      config = %Tinkex.Config{
        base_url: "https://example.com",
        api_key: "tml-test-key",
        timeout: 60_000,
        max_retries: 3
      }

      assert API.client_module(config: config) == Tinkex.API
    end

    test "returns Tinkex.API when no options provided" do
      assert API.client_module([]) == Tinkex.API
    end
  end

  describe "default implementation" do
    test "post/3 returns not implemented error" do
      assert {:error, %Error{type: :api_connection}} = API.post("/test", %{}, [])
    end

    test "get/2 returns not implemented error" do
      assert {:error, %Error{type: :api_connection}} = API.get("/test", [])
    end

    test "delete/2 returns not implemented error" do
      assert {:error, %Error{type: :api_connection}} = API.delete("/test", [])
    end
  end
end
