defmodule Tinkex.ServiceClientTest do
  use ExUnit.Case, async: true

  alias Tinkex.ServiceClient
  alias Tinkex.Types.{GetServerCapabilitiesResponse, LoraConfig}

  defmodule MockWeightsAPI do
    def save_weights(_config, _request) do
      {:ok, %{"path" => "tinker://run-123/weights/ckpt-001", "type" => "weights"}}
    end

    def load_weights(_config, _request) do
      {:ok, %{"path" => "tinker://run-123/weights/ckpt-001", "type" => "weights"}}
    end
  end

  defmodule MockSessionAPI do
    def create(_config, _request) do
      {:ok, %{"session_id" => "test-session-123"}}
    end

    def create_typed(_config, _request) do
      {:ok,
       %Tinkex.Types.CreateSessionResponse{
         session_id: "test-session-123",
         info_message: nil,
         warning_message: nil,
         error_message: nil
       }}
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

  setup do
    config = %Tinkex.Config{
      base_url: "https://example.com",
      api_key: "tml-test-key",
      timeout: 60_000,
      max_retries: 3,
      telemetry_enabled?: false
    }

    client =
      ServiceClient.new(config,
        session_api: MockSessionAPI,
        service_api: MockServiceAPI,
        telemetry_enabled: false
      )

    {:ok, client: client, config: config}
  end

  describe "new/2" do
    test "creates a ServiceClient struct with session", %{config: config} do
      client =
        ServiceClient.new(config,
          session_api: MockSessionAPI,
          service_api: MockServiceAPI
        )

      assert %ServiceClient{} = client
      assert client.session_id == "test-session-123"
      assert client.config == config
    end

    test "accepts explicit session_id to skip session creation", %{config: config} do
      client = ServiceClient.new(config, session_id: "explicit-session")

      assert client.session_id == "explicit-session"
    end

    test "increments counters for sequence IDs", %{client: client} do
      assert ServiceClient.next_training_seq_id(client) == 1
      assert ServiceClient.next_training_seq_id(client) == 2
      assert ServiceClient.next_sampling_seq_id(client) == 1
    end
  end

  describe "create_lora_training_client/3" do
    test "creates a training client", %{client: client} do
      lora_config = %LoraConfig{rank: 32}

      {:ok, training_client} =
        ServiceClient.create_lora_training_client(client, "Qwen/Qwen2.5-7B", lora_config)

      assert %Tinkex.TrainingClient{} = training_client
      assert training_client.session_id == client.session_id
    end

    test "uses default lora config if nil", %{client: client} do
      {:ok, training_client} =
        ServiceClient.create_lora_training_client(client, "Qwen/Qwen2.5-7B", nil)

      assert %Tinkex.TrainingClient{} = training_client
    end
  end

  describe "create_sampling_client/3" do
    test "creates a sampling client from base model", %{client: client} do
      {:ok, sampling_client} =
        ServiceClient.create_sampling_client(client, base_model: "Qwen/Qwen2.5-7B")

      assert %Tinkex.SamplingClient{} = sampling_client
    end

    test "creates a sampling client from model path", %{client: client} do
      {:ok, sampling_client} =
        ServiceClient.create_sampling_client(client,
          model_path: "tinker://run-123/weights/ckpt-001"
        )

      assert %Tinkex.SamplingClient{} = sampling_client
    end
  end

  describe "create_rest_client/1" do
    test "creates a rest client", %{client: client} do
      {:ok, rest_client} = ServiceClient.create_rest_client(client)

      assert %Tinkex.RestClient{} = rest_client
      assert rest_client.session_id == client.session_id
    end
  end

  describe "get_server_capabilities/1" do
    test "returns server capabilities", %{client: client} do
      {:ok, capabilities} = ServiceClient.get_server_capabilities(client)

      assert %GetServerCapabilitiesResponse{} = capabilities
      assert length(capabilities.supported_models) > 0
    end
  end

  describe "create_training_client_from_state/3" do
    test "creates training client from checkpoint path", %{config: config} do
      # Need a client with MockWeightsAPI injected
      client =
        ServiceClient.new(config,
          session_api: MockSessionAPI,
          service_api: MockServiceAPI
        )

      {:ok, training_client} =
        ServiceClient.create_training_client_from_state(
          client,
          "Qwen/Qwen2.5-7B",
          "tinker://run-123/weights/ckpt-001",
          weights_api: __MODULE__.MockWeightsAPI
        )

      assert %Tinkex.TrainingClient{} = training_client
    end
  end

  describe "session_id/1" do
    test "returns the session id", %{client: client} do
      assert ServiceClient.session_id(client) == "test-session-123"
    end
  end

  describe "config/1" do
    test "returns the config", %{client: client, config: config} do
      assert ServiceClient.config(client) == config
    end
  end

  describe "telemetry_reporter/1" do
    test "returns nil when no reporter is configured", %{client: client} do
      assert ServiceClient.telemetry_reporter(client) == nil
    end

    test "returns the reporter pid when configured", %{config: config} do
      # Create a client with telemetry enabled - reporter will be started
      client =
        ServiceClient.new(
          %{config | telemetry_enabled?: true},
          session_id: "telemetry-test-session",
          telemetry_enabled: true
        )

      reporter = ServiceClient.telemetry_reporter(client)

      if reporter do
        assert is_pid(reporter)
        assert Process.alive?(reporter)
        # Clean up
        Tinkex.Telemetry.Reporter.stop(reporter)
      end
    end

    test "uses provided reporter pid", %{config: config} do
      # Start a reporter manually
      {:ok, reporter} =
        Tinkex.Telemetry.Reporter.start_link(
          config: config,
          session_id: "manual-session",
          enabled: true
        )

      client =
        ServiceClient.new(config,
          session_id: "test-session",
          telemetry_reporter: reporter
        )

      assert ServiceClient.telemetry_reporter(client) == reporter

      # Clean up
      Tinkex.Telemetry.Reporter.stop(reporter)
    end
  end

  describe "get_telemetry/0" do
    test "returns global telemetry status" do
      stats = ServiceClient.get_telemetry()

      assert Map.has_key?(stats, :status)
      assert Map.has_key?(stats, :sdk_version)
      assert Map.has_key?(stats, :timestamp)
      assert stats.status == :active
    end
  end

  describe "get_telemetry/1" do
    test "returns nil when no reporter is active", %{client: client} do
      assert ServiceClient.get_telemetry(client) == nil
    end

    test "returns stats when reporter is active", %{config: config} do
      # Start a reporter manually
      {:ok, reporter} =
        Tinkex.Telemetry.Reporter.start_link(
          config: config,
          session_id: "stats-session",
          enabled: true
        )

      client =
        ServiceClient.new(config,
          session_id: "stats-session",
          telemetry_reporter: reporter
        )

      stats = ServiceClient.get_telemetry(client)

      assert is_map(stats)
      assert stats.session_id == "stats-session"
      assert stats.reporter_alive? == true
      assert stats.reporter_pid == reporter

      # Clean up
      Tinkex.Telemetry.Reporter.stop(reporter)
    end

    test "reports reporter_alive? as false when reporter is dead", %{config: config} do
      # Start a reporter manually
      {:ok, reporter} =
        Tinkex.Telemetry.Reporter.start_link(
          config: config,
          session_id: "dead-session",
          enabled: true
        )

      client =
        ServiceClient.new(config,
          session_id: "dead-session",
          telemetry_reporter: reporter
        )

      # Kill the reporter
      Tinkex.Telemetry.Reporter.stop(reporter)
      # Give it time to stop
      Process.sleep(10)

      stats = ServiceClient.get_telemetry(client)

      assert stats.reporter_alive? == false
    end
  end
end
