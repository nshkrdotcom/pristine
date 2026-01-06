defmodule Tinkex.TrainingClientTest do
  use ExUnit.Case, async: true

  alias Tinkex.TrainingClient

  alias Tinkex.Types.{
    AdamParams,
    Datum,
    ForwardBackwardInput,
    ForwardBackwardOutput,
    ModelInput,
    OptimStepResponse,
    SaveWeightsResponse,
    TensorData
  }

  defmodule MockTrainingAPI do
    def forward_backward_future(_config, request) do
      seq_id = request["seq_id"] || request[:seq_id]
      {:ok, %{"request_id" => "fb-future-#{seq_id}"}}
    end

    def forward_future(_config, request) do
      seq_id = request["seq_id"] || request[:seq_id]
      {:ok, %{"request_id" => "fwd-future-#{seq_id}"}}
    end

    def optim_step_future(_config, request) do
      seq_id = request["seq_id"] || request[:seq_id]
      {:ok, %{"request_id" => "optim-future-#{seq_id}"}}
    end
  end

  defmodule MockWeightsAPI do
    def save_weights(_config, _request) do
      {:ok, %{"path" => "tinker://run-123/weights/ckpt-001", "type" => "weights"}}
    end

    def load_weights(_config, _request) do
      {:ok, %{"path" => "tinker://run-123/weights/ckpt-001", "type" => "weights"}}
    end

    def save_weights_for_sampler(_config, _request) do
      {:ok,
       %{
         "path" => "tinker://run-123/sampler/ckpt-001",
         "sampling_session_id" => "sampling-456",
         "type" => "sampler"
       }}
    end
  end

  defmodule MockModelsAPI do
    def get_info(_config, _request) do
      {:ok,
       %Tinkex.Types.GetInfoResponse{
         model_id: "model-123",
         model_data: %{
           "arch" => "llama",
           "model_name" => "test-model/TestModel-8B",
           "tokenizer_id" => nil
         }
       }}
    end

    def unload_model(_config, _request) do
      {:ok, %Tinkex.Types.UnloadModelResponse{model_id: "model-123", type: "unload_model"}}
    end
  end

  defmodule MockModelsAPIFuture do
    def get_info(_config, _request) do
      {:ok,
       %Tinkex.Types.GetInfoResponse{
         model_id: "model-123",
         model_data: %{"model_name" => "test-model"}
       }}
    end

    def unload_model(_config, _request) do
      {:ok, %{"request_id" => "unload-future-123"}}
    end
  end

  defmodule MockFutures do
    def poll(_config, _request_id, _opts) do
      Task.async(fn ->
        {:ok,
         %{
           "loss_fn_output_type" => "CrossEntropy",
           "loss_fn_outputs" => [%{"loss" => 0.5}],
           "metrics" => %{"loss" => 0.5, "grad_norm" => 1.0}
         }}
      end)
    end
  end

  setup do
    config = %Tinkex.Config{
      base_url: "https://example.com",
      api_key: "tml-test-key",
      timeout: 60_000,
      max_retries: 3
    }

    client =
      TrainingClient.new(
        "model-123",
        "session-abc",
        config,
        training_api: MockTrainingAPI,
        weights_api: MockWeightsAPI,
        futures_api: MockFutures
      )

    {:ok, client: client, config: config}
  end

  describe "new/4" do
    test "creates a TrainingClient struct", %{config: config} do
      client = TrainingClient.new("model-id", "session-id", config)

      assert %TrainingClient{} = client
      assert client.model_id == "model-id"
      assert client.session_id == "session-id"
      assert client.config == config
    end

    test "accepts optional api modules", %{config: config} do
      client =
        TrainingClient.new("model-id", "session-id", config,
          training_api: MockTrainingAPI,
          weights_api: MockWeightsAPI
        )

      assert client.training_api == MockTrainingAPI
      assert client.weights_api == MockWeightsAPI
    end
  end

  describe "forward_backward/4" do
    test "submits forward-backward request and returns polling task", %{client: client} do
      data = [
        Datum.new(%{model_input: ModelInput.from_ints([1, 2, 3])})
      ]

      input = %ForwardBackwardInput{
        data: data,
        loss_fn: :cross_entropy,
        loss_fn_config: %{}
      }

      {:ok, task} = TrainingClient.forward_backward(client, input)

      assert %Task{} = task
      {:ok, response} = Task.await(task)
      assert response["metrics"]["loss"]
    end

    test "accepts data list directly", %{client: client} do
      data = [
        Datum.new(%{model_input: ModelInput.from_ints([1, 2, 3])})
      ]

      {:ok, task} = TrainingClient.forward_backward(client, data, :cross_entropy)

      assert %Task{} = task
    end
  end

  describe "forward/3" do
    test "submits forward-only request", %{client: client} do
      data = [
        Datum.new(%{model_input: ModelInput.from_ints([1, 2, 3])})
      ]

      {:ok, task} = TrainingClient.forward(client, data)

      assert %Task{} = task
    end
  end

  describe "optim_step/3" do
    test "submits optimizer step request", %{client: client} do
      adam_params = %AdamParams{
        learning_rate: 0.001,
        beta1: 0.9,
        beta2: 0.99
      }

      {:ok, task} = TrainingClient.optim_step(client, adam_params)

      assert %Task{} = task
    end
  end

  describe "save_state/3" do
    test "saves model weights with default type", %{client: client} do
      {:ok, response} = TrainingClient.save_state(client, "checkpoint-1")

      assert %SaveWeightsResponse{} = response
      assert response.path =~ "tinker://"
    end

    test "saves with optimizer state", %{client: client} do
      {:ok, response} =
        TrainingClient.save_state(client, "checkpoint-1", include_optimizer: true)

      assert %SaveWeightsResponse{} = response
    end
  end

  describe "load_state/3" do
    test "loads model weights", %{client: client} do
      {:ok, response} =
        TrainingClient.load_state(client, "tinker://run-123/weights/ckpt-001")

      assert response.path =~ "tinker://"
    end
  end

  describe "save_weights_for_sampler/3" do
    test "saves weights for sampling use", %{client: client} do
      {:ok, response} = TrainingClient.save_weights_for_sampler(client, "sampler-ckpt")

      assert response["sampling_session_id"]
    end
  end

  describe "next_seq_id/1" do
    test "returns incrementing sequence IDs", %{client: client} do
      seq1 = TrainingClient.next_seq_id(client)
      seq2 = TrainingClient.next_seq_id(client)

      assert is_integer(seq1)
      assert is_integer(seq2)
      assert seq2 > seq1
    end
  end

  describe "parse_forward_backward_response/1" do
    test "parses ForwardBackwardOutput from response" do
      response = %{
        "loss_fn_output_type" => "CrossEntropy",
        "loss_fn_outputs" => [%{"loss" => 0.45}],
        "metrics" => %{"loss" => 0.45, "grad_norm" => 1.2}
      }

      {:ok, output} = TrainingClient.parse_forward_backward_response(response)

      assert %ForwardBackwardOutput{} = output
      assert output.loss_fn_output_type == "CrossEntropy"
      assert output.metrics["loss"] == 0.45
    end
  end

  describe "get_info/1" do
    test "retrieves model info from API", %{config: config} do
      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          models_api: MockModelsAPI
        )

      {:ok, response} = TrainingClient.get_info(client)

      assert %Tinkex.Types.GetInfoResponse{} = response
      assert response.model_id == "model-123"
      assert response.model_data["arch"] == "llama"
    end

    test "propagates API errors", %{config: config} do
      defmodule ErrorModelsAPI do
        def get_info(_config, _request) do
          {:error, Tinkex.Error.new(:network_error, "Connection failed")}
        end
      end

      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          models_api: ErrorModelsAPI
        )

      {:error, error} = TrainingClient.get_info(client)

      assert %Tinkex.Error{type: :network_error} = error
    end
  end

  describe "unload_model/1" do
    test "unloads model with direct response", %{config: config} do
      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          models_api: MockModelsAPI
        )

      {:ok, response} = TrainingClient.unload_model(client)

      assert %Tinkex.Types.UnloadModelResponse{} = response
      assert response.model_id == "model-123"
    end

    test "handles future-based unload response", %{config: config} do
      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          models_api: MockModelsAPIFuture,
          futures_api: MockFutures
        )

      {:ok, response} = TrainingClient.unload_model(client)

      # Future gets polled and awaited, returning the result
      assert response
    end
  end

  describe "get_tokenizer/2" do
    test "gets tokenizer using model info", %{config: config} do
      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          models_api: MockModelsAPI
        )

      # Use custom load_fun to avoid actual HuggingFace calls
      mock_tokenizer = %{id: "mock-tokenizer"}
      load_fun = fn _id, _opts -> {:ok, mock_tokenizer} end

      {:ok, tokenizer} = TrainingClient.get_tokenizer(client, load_fun: load_fun)

      assert tokenizer == mock_tokenizer
    end

    test "propagates info fetch errors", %{config: config} do
      defmodule InfoErrorModelsAPI do
        def get_info(_config, _request) do
          {:error, Tinkex.Error.new(:network_error, "Info fetch failed")}
        end
      end

      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          models_api: InfoErrorModelsAPI
        )

      {:error, error} = TrainingClient.get_tokenizer(client)

      assert %Tinkex.Error{type: :network_error} = error
    end
  end

  describe "encode/3" do
    test "calls tokenizer encode with resolved model name", %{config: config} do
      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          models_api: MockModelsAPI
        )

      # Clear cache to ensure load_fun is called (not cached value from other tests)
      tokenizer_id = "test-model/TestModel-8B"
      Tinkex.Tokenizer.__supertester_clear_cache__(tokenizer_id)

      # Use a load function that we can detect was called
      test_pid = self()

      load_fun = fn tid, _opts ->
        send(test_pid, {:load_called, tid})
        {:error, Tinkex.Error.new(:validation, "Test tokenizer not found")}
      end

      # Result should be an error from our load function
      result = TrainingClient.encode(client, "test", load_fun: load_fun)

      # Verify that load was called with the model name from MockModelsAPI
      # MockModelsAPI returns model_name: "test-model/TestModel-8B"
      assert_received {:load_called, ^tokenizer_id}
      assert {:error, %Tinkex.Error{}} = result
    end

    test "propagates info errors", %{config: config} do
      defmodule EncodeInfoErrorAPI do
        def get_info(_config, _request) do
          {:error, Tinkex.Error.new(:timeout, "Request timed out")}
        end
      end

      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          models_api: EncodeInfoErrorAPI
        )

      {:error, error} = TrainingClient.encode(client, "hello")

      assert %Tinkex.Error{type: :timeout} = error
    end
  end

  describe "decode/3" do
    test "propagates info errors", %{config: config} do
      defmodule DecodeInfoErrorAPI do
        def get_info(_config, _request) do
          {:error, Tinkex.Error.new(:timeout, "Request timed out")}
        end
      end

      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          models_api: DecodeInfoErrorAPI
        )

      {:error, error} = TrainingClient.decode(client, [1, 2, 3])

      assert %Tinkex.Error{type: :timeout} = error
    end
  end

  # ---------------------------------------------------------------------------
  # forward_backward_custom/4 Tests
  # ---------------------------------------------------------------------------

  describe "forward_backward_custom/4" do
    defmodule CustomLossTrainingAPI do
      @doc """
      Mock training API that returns forward outputs with logprobs for custom loss.
      """
      def forward_backward_future(_config, request) do
        seq_id = request["seq_id"] || request[:seq_id]
        {:ok, %{"request_id" => "fb-custom-#{seq_id}"}}
      end

      def forward_future(_config, request) do
        seq_id = request["seq_id"] || request[:seq_id]
        {:ok, %{"request_id" => "fwd-custom-#{seq_id}"}}
      end

      def optim_step_future(_config, request) do
        seq_id = request["seq_id"] || request[:seq_id]
        {:ok, %{"request_id" => "optim-custom-#{seq_id}"}}
      end
    end

    defmodule CustomLossFutures do
      @doc """
      Mock futures that returns forward output with logprobs.
      """
      def poll(_config, "fwd-custom-" <> _, _opts) do
        # Return forward output with logprobs for each datum
        Task.async(fn ->
          {:ok,
           %{
             "loss_fn_output_type" => "cross_entropy",
             "loss_fn_outputs" => [
               %{"logprobs" => %{"data" => [-1.0, -2.0, -3.0], "dtype" => "float32"}}
             ],
             "metrics" => %{"loss" => 2.0}
           }}
        end)
      end

      def poll(_config, "fb-custom-" <> _, _opts) do
        # Return backward output with metrics
        Task.async(fn ->
          {:ok,
           %{
             "loss_fn_output_type" => "linear_weighted",
             "loss_fn_outputs" => [%{"loss" => 0.5}],
             "metrics" => %{"loss" => 0.5, "grad_norm" => 1.5}
           }}
        end)
      end
    end

    test "executes custom loss with gradient computation", %{config: config} do
      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          training_api: CustomLossTrainingAPI,
          futures_api: CustomLossFutures
        )

      # Create data with target_tokens (required for custom loss)
      data = [
        %Datum{
          model_input: ModelInput.from_ints([1, 2, 3]),
          loss_fn_inputs: %{
            "target_tokens" => %TensorData{data: [4, 5, 6], dtype: :int64}
          }
        }
      ]

      # Custom loss function: sum of logprobs
      loss_fn = fn _data, logprobs ->
        total = logprobs |> Enum.map(&Nx.sum/1) |> Enum.reduce(&Nx.add/2)
        {total, %{"custom_metric" => 42.0}}
      end

      {:ok, task} = TrainingClient.forward_backward_custom(client, data, loss_fn)

      assert %Task{} = task
      {:ok, output} = Task.await(task)

      # Output should be a ForwardBackwardOutput with merged metrics
      assert output["loss_fn_output_type"] == "linear_weighted"
      # Custom metrics should be merged
      assert output["custom_metric"] == 42.0
    end

    test "handles empty data", %{config: config} do
      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          training_api: CustomLossTrainingAPI,
          futures_api: CustomLossFutures
        )

      loss_fn = fn _data, _logprobs -> {Nx.tensor(0.0), %{}} end

      {:ok, task} = TrainingClient.forward_backward_custom(client, [], loss_fn)

      {:ok, output} = Task.await(task)
      assert output
    end

    test "propagates forward errors", %{config: config} do
      defmodule ErrorFutures do
        def poll(_config, _request_id, _opts) do
          Task.async(fn ->
            {:error, Tinkex.Error.new(:request_failed, "Forward failed")}
          end)
        end
      end

      client =
        TrainingClient.new(
          "model-123",
          "session-abc",
          config,
          training_api: CustomLossTrainingAPI,
          futures_api: ErrorFutures
        )

      data = [
        %Datum{
          model_input: ModelInput.from_ints([1, 2, 3]),
          loss_fn_inputs: %{
            "target_tokens" => %TensorData{data: [4, 5, 6], dtype: :int64}
          }
        }
      ]

      loss_fn = fn _data, logprobs ->
        total = logprobs |> Enum.map(&Nx.sum/1) |> Enum.reduce(&Nx.add/2)
        {total, %{}}
      end

      {:ok, task} = TrainingClient.forward_backward_custom(client, data, loss_fn)

      {:error, error} = Task.await(task)
      assert %Tinkex.Error{} = error
    end
  end
end
