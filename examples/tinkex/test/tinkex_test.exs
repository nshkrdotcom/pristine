defmodule TinkexTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{GetServerCapabilitiesResponse, LoraConfig}

  defmodule MockSessionAPI do
    def create(_config, _request) do
      {:ok, %{"session_id" => "test-session-123"}}
    end
  end

  defmodule MockServiceAPI do
    def create_model(_config, _request) do
      {:ok, %{"model_id" => "model-456"}}
    end

    def create_sampling_session(_config, _request) do
      {:ok, %{"sampling_session_id" => "sampling-789"}}
    end

    def get_server_capabilities(_config) do
      {:ok,
       %{
         "supported_models" => [
           %{"model_id" => "qwen", "model_name" => "Qwen/Qwen2.5-7B", "arch" => "qwen2"}
         ]
       }}
    end
  end

  describe "new/1" do
    test "creates a ServiceClient with config options" do
      client =
        Tinkex.new(
          api_key: "tml-test-key",
          session_api: MockSessionAPI,
          service_api: MockServiceAPI
        )

      assert %Tinkex.ServiceClient{} = client
      assert client.session_id == "test-session-123"
    end

    test "accepts explicit session_id" do
      client =
        Tinkex.new(
          api_key: "tml-test-key",
          session_id: "explicit-session"
        )

      assert client.session_id == "explicit-session"
    end
  end

  describe "new!/1" do
    test "creates a ServiceClient or raises" do
      client =
        Tinkex.new!(
          api_key: "tml-test-key",
          session_api: MockSessionAPI,
          service_api: MockServiceAPI
        )

      assert %Tinkex.ServiceClient{} = client
    end
  end

  describe "create_training_client/3" do
    test "delegates to ServiceClient" do
      client =
        Tinkex.new(
          api_key: "tml-test-key",
          session_api: MockSessionAPI,
          service_api: MockServiceAPI
        )

      {:ok, training} = Tinkex.create_training_client(client, "Qwen/Qwen2.5-7B")

      assert %Tinkex.TrainingClient{} = training
    end

    test "accepts lora_config option" do
      client =
        Tinkex.new(
          api_key: "tml-test-key",
          session_api: MockSessionAPI,
          service_api: MockServiceAPI
        )

      lora = %LoraConfig{rank: 64}

      {:ok, training} =
        Tinkex.create_training_client(client, "Qwen/Qwen2.5-7B", lora_config: lora)

      assert %Tinkex.TrainingClient{} = training
    end
  end

  describe "create_sampling_client/2" do
    test "delegates to ServiceClient" do
      client =
        Tinkex.new(
          api_key: "tml-test-key",
          session_api: MockSessionAPI,
          service_api: MockServiceAPI
        )

      {:ok, sampler} = Tinkex.create_sampling_client(client, base_model: "Qwen/Qwen2.5-7B")

      assert %Tinkex.SamplingClient{} = sampler
    end
  end

  describe "create_rest_client/1" do
    test "delegates to ServiceClient" do
      client =
        Tinkex.new(
          api_key: "tml-test-key",
          session_api: MockSessionAPI,
          service_api: MockServiceAPI
        )

      {:ok, rest} = Tinkex.create_rest_client(client)

      assert %Tinkex.RestClient{} = rest
    end
  end

  describe "get_server_capabilities/1" do
    test "delegates to ServiceClient" do
      client =
        Tinkex.new(
          api_key: "tml-test-key",
          session_api: MockSessionAPI,
          service_api: MockServiceAPI
        )

      {:ok, capabilities} = Tinkex.get_server_capabilities(client)

      assert %GetServerCapabilitiesResponse{} = capabilities
    end
  end

  describe "version/0" do
    test "returns the SDK version" do
      assert Tinkex.version() =~ ~r/^\d+\.\d+\.\d+/
    end
  end
end
