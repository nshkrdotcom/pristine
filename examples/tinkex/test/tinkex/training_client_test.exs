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
end
