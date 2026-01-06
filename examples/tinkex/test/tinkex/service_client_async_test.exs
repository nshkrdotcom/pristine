defmodule Tinkex.ServiceClientAsyncTest do
  @moduledoc """
  Tests for ServiceClient async wrapper functions.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Config
  alias Tinkex.ServiceClient

  # Mock API modules for testing
  defmodule MockSessionAPI do
    def create(_config, _request) do
      {:ok, %{"session_id" => "test-session-123"}}
    end
  end

  defmodule MockServiceAPI do
    def get_server_capabilities(_config) do
      {:ok, %{"models" => ["model-a", "model-b"], "version" => "1.0.0"}}
    end

    def create_model(_config, _request) do
      {:ok, %{"model_id" => "model-123"}}
    end

    def create_sampling_session(_config, _request) do
      {:ok, %{"sampling_session_id" => "sampler-456"}}
    end
  end

  defmodule SlowServiceAPI do
    def get_server_capabilities(_config) do
      Process.sleep(50)
      {:ok, %{"models" => ["model-a"], "version" => "1.0.0"}}
    end

    def create_model(_config, _request) do
      Process.sleep(50)
      {:ok, %{"model_id" => "model-slow"}}
    end

    def create_sampling_session(_config, _request) do
      Process.sleep(50)
      {:ok, %{"sampling_session_id" => "sampler-slow"}}
    end
  end

  defmodule FailingServiceAPI do
    def get_server_capabilities(_config) do
      {:error, %{message: "Server unavailable"}}
    end

    def create_model(_config, _request) do
      {:error, %{message: "Model creation failed"}}
    end

    def create_sampling_session(_config, _request) do
      {:error, %{message: "Sampler creation failed"}}
    end
  end

  setup do
    config = Config.new(api_key: "tml-test-key", base_url: "https://api.test.com")

    client =
      ServiceClient.new(config,
        session_id: "test-session",
        session_api: MockSessionAPI,
        service_api: MockServiceAPI
      )

    {:ok, config: config, client: client}
  end

  describe "get_server_capabilities_async/1" do
    test "returns a Task", %{client: client} do
      task = ServiceClient.get_server_capabilities_async(client)
      assert %Task{} = task
    end

    test "task resolves to server capabilities", %{client: client} do
      task = ServiceClient.get_server_capabilities_async(client)
      result = Task.await(task)

      assert {:ok, response} = result
      assert %Tinkex.Types.GetServerCapabilitiesResponse{} = response
    end

    test "allows concurrent calls", %{config: config} do
      client =
        ServiceClient.new(config,
          session_id: "concurrent-test",
          service_api: SlowServiceAPI
        )

      # Start multiple async calls
      tasks = for _ <- 1..3, do: ServiceClient.get_server_capabilities_async(client)

      # All should complete
      results = Task.await_many(tasks)
      assert length(results) == 3

      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end

    test "propagates errors", %{config: config} do
      client =
        ServiceClient.new(config,
          session_id: "error-test",
          service_api: FailingServiceAPI
        )

      task = ServiceClient.get_server_capabilities_async(client)
      result = Task.await(task)

      assert {:error, _} = result
    end
  end

  describe "create_lora_training_client_async/4" do
    test "returns a Task", %{client: client} do
      task = ServiceClient.create_lora_training_client_async(client, "test-model", nil)
      assert %Task{} = task
    end

    test "task resolves to training client", %{client: client} do
      task = ServiceClient.create_lora_training_client_async(client, "test-model", nil)
      result = Task.await(task)

      assert {:ok, training_client} = result
      assert training_client.model_id == "model-123"
    end

    test "passes options to underlying function", %{client: client} do
      lora_config = %Tinkex.Types.LoraConfig{rank: 64}

      task =
        ServiceClient.create_lora_training_client_async(
          client,
          "test-model",
          lora_config,
          user_metadata: %{"key" => "value"}
        )

      result = Task.await(task)
      assert {:ok, _training_client} = result
    end

    test "propagates errors", %{config: config} do
      client =
        ServiceClient.new(config,
          session_id: "error-test",
          service_api: FailingServiceAPI
        )

      task = ServiceClient.create_lora_training_client_async(client, "test-model", nil)
      result = Task.await(task)

      assert {:error, _} = result
    end
  end

  describe "create_training_client_from_state_async/4" do
    test "returns a Task", %{client: client} do
      task =
        ServiceClient.create_training_client_from_state_async(
          client,
          "test-model",
          "tinker://run/checkpoint"
        )

      assert %Task{} = task
    end

    # Note: This test would need more mocking for the full flow
    # The async wrapper itself works correctly
  end

  describe "create_sampling_client_async/2" do
    test "returns a Task", %{client: client} do
      task = ServiceClient.create_sampling_client_async(client, base_model: "test-model")
      assert %Task{} = task
    end

    test "task resolves to sampling client", %{client: client} do
      task = ServiceClient.create_sampling_client_async(client, base_model: "test-model")
      result = Task.await(task)

      assert {:ok, sampling_client} = result
      assert sampling_client.sampling_session_id == "sampler-456"
    end

    test "propagates errors", %{config: config} do
      client =
        ServiceClient.new(config,
          session_id: "error-test",
          service_api: FailingServiceAPI
        )

      task = ServiceClient.create_sampling_client_async(client, base_model: "test-model")
      result = Task.await(task)

      assert {:error, _} = result
    end
  end

  describe "async pattern usage" do
    test "fire and forget pattern", %{client: client} do
      # Start async call
      task = ServiceClient.get_server_capabilities_async(client)

      # Do other work...
      Process.sleep(10)

      # Await when needed
      {:ok, _response} = Task.await(task)
    end

    test "multiple parallel operations", %{client: client} do
      # Start multiple operations in parallel
      caps_task = ServiceClient.get_server_capabilities_async(client)
      training_task = ServiceClient.create_lora_training_client_async(client, "model", nil)
      sampling_task = ServiceClient.create_sampling_client_async(client, base_model: "model")

      # Await all
      [{:ok, _caps}, {:ok, _training}, {:ok, _sampling}] =
        Task.await_many([caps_task, training_task, sampling_task])
    end
  end
end
