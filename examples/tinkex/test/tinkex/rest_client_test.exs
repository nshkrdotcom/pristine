defmodule Tinkex.RestClientTest do
  use ExUnit.Case, async: true

  alias Tinkex.RestClient

  alias Tinkex.Types.{
    GetSessionResponse,
    ListSessionsResponse,
    CheckpointsListResponse,
    TrainingRun,
    TrainingRunsResponse,
    GetSamplerResponse,
    WeightsInfoResponse
  }

  defmodule MockRestAPI do
    def get_session(_config, session_id) do
      {:ok, %{"training_run_ids" => ["run-#{session_id}"], "sampler_ids" => ["sampler-1"]}}
    end

    def list_sessions(_config, _limit, _offset) do
      {:ok, %{"sessions" => ["session-1", "session-2"]}}
    end

    def list_checkpoints(_config, run_id) do
      {:ok,
       %{
         "checkpoints" => [
           %{
             "checkpoint_id" => "ckpt-001",
             "checkpoint_type" => "weights",
             "tinker_path" => "tinker://#{run_id}/weights/ckpt-001",
             "public" => false
           }
         ],
         "cursor" => %{"offset" => 0, "limit" => 100, "total_count" => 1}
       }}
    end

    def list_user_checkpoints(_config, _limit, _offset) do
      {:ok,
       %{
         "checkpoints" => [
           %{
             "checkpoint_id" => "ckpt-001",
             "checkpoint_type" => "weights",
             "tinker_path" => "tinker://run-123/weights/ckpt-001",
             "public" => false
           }
         ],
         "cursor" => %{"offset" => 0, "limit" => 100, "total_count" => 1}
       }}
    end

    def get_checkpoint_archive_url(_config, tinker_path) when is_binary(tinker_path) do
      {:ok, %{"url" => "https://storage.example.com/archive.tar.gz", "expires" => nil}}
    end

    def get_checkpoint_archive_url(_config, _run_id, _checkpoint_id) do
      {:ok, %{"url" => "https://storage.example.com/archive.tar.gz", "expires" => nil}}
    end

    def delete_checkpoint(_config, tinker_path) when is_binary(tinker_path) do
      {:ok, %{"deleted" => true}}
    end

    def delete_checkpoint(_config, _run_id, _checkpoint_id) do
      {:ok, %{"deleted" => true}}
    end

    def publish_checkpoint(_config, _tinker_path) do
      {:ok, %{"published" => true}}
    end

    def unpublish_checkpoint(_config, _tinker_path) do
      {:ok, %{"unpublished" => true}}
    end

    def get_training_run(_config, training_run_id) do
      {:ok,
       %TrainingRun{
         training_run_id: training_run_id,
         base_model: "Qwen/Qwen2.5-7B",
         model_owner: "user-1",
         is_lora: true,
         lora_rank: 32,
         corrupted: false,
         last_request_time: "2024-01-01T00:00:00Z"
       }}
    end

    def get_training_run_by_tinker_path(_config, _tinker_path) do
      {:ok,
       %TrainingRun{
         training_run_id: "run-123",
         base_model: "Qwen/Qwen2.5-7B",
         model_owner: "user-1",
         is_lora: true,
         lora_rank: 32,
         corrupted: false,
         last_request_time: "2024-01-01T00:00:00Z"
       }}
    end

    def list_training_runs(_config, _limit, _offset) do
      {:ok,
       %TrainingRunsResponse{
         training_runs: [
           %TrainingRun{
             training_run_id: "run-123",
             base_model: "Qwen/Qwen2.5-7B",
             model_owner: "user-1",
             is_lora: true,
             lora_rank: 32,
             corrupted: false,
             last_request_time: "2024-01-01T00:00:00Z"
           }
         ],
         cursor: nil
       }}
    end

    def get_sampler(_config, _sampler_id) do
      {:ok,
       %GetSamplerResponse{
         sampler_id: "session-id:sample:0",
         base_model: "Qwen/Qwen2.5-7B",
         model_path: "tinker://run-123/weights/ckpt-001"
       }}
    end

    def get_weights_info_by_tinker_path(_config, _tinker_path) do
      {:ok,
       %WeightsInfoResponse{
         base_model: "Qwen/Qwen2.5-7B",
         is_lora: true,
         lora_rank: 32
       }}
    end
  end

  setup do
    config = %Tinkex.Config{
      base_url: "https://example.com",
      api_key: "tml-test-key",
      timeout: 60_000,
      max_retries: 3
    }

    client = RestClient.new("session-abc", config, rest_api: MockRestAPI)

    {:ok, client: client, config: config}
  end

  describe "new/3" do
    test "creates a RestClient struct", %{config: config} do
      client = RestClient.new("session-123", config)

      assert %RestClient{} = client
      assert client.session_id == "session-123"
      assert client.config == config
    end
  end

  describe "get_session/2" do
    test "returns GetSessionResponse", %{client: client} do
      {:ok, response} = RestClient.get_session(client, "session-123")

      assert %GetSessionResponse{} = response
      assert response.training_run_ids == ["run-session-123"]
    end
  end

  describe "list_sessions/2" do
    test "returns ListSessionsResponse with default options", %{client: client} do
      {:ok, response} = RestClient.list_sessions(client)

      assert %ListSessionsResponse{} = response
      assert response.sessions == ["session-1", "session-2"]
    end

    test "accepts limit and offset options", %{client: client} do
      {:ok, _response} = RestClient.list_sessions(client, limit: 50, offset: 10)
    end
  end

  describe "list_checkpoints/2" do
    test "returns CheckpointsListResponse", %{client: client} do
      {:ok, response} = RestClient.list_checkpoints(client, "run-123")

      assert %CheckpointsListResponse{} = response
      assert length(response.checkpoints) == 1
    end
  end

  describe "list_user_checkpoints/2" do
    test "returns CheckpointsListResponse with default options", %{client: client} do
      {:ok, response} = RestClient.list_user_checkpoints(client)

      assert %CheckpointsListResponse{} = response
    end

    test "accepts limit and offset options", %{client: client} do
      {:ok, _response} = RestClient.list_user_checkpoints(client, limit: 50, offset: 10)
    end
  end

  describe "get_checkpoint_archive_url/2" do
    test "returns archive URL by tinker path", %{client: client} do
      {:ok, response} =
        RestClient.get_checkpoint_archive_url(
          client,
          "tinker://run-123/weights/ckpt-001"
        )

      assert response.url =~ "storage.example.com"
    end
  end

  describe "get_checkpoint_archive_url/3" do
    test "returns archive URL by run_id and checkpoint_id", %{client: client} do
      {:ok, response} = RestClient.get_checkpoint_archive_url(client, "run-123", "ckpt-001")

      assert response.url =~ "storage.example.com"
    end
  end

  describe "delete_checkpoint/2" do
    test "deletes checkpoint by tinker path", %{client: client} do
      {:ok, response} =
        RestClient.delete_checkpoint(
          client,
          "tinker://run-123/weights/ckpt-001"
        )

      assert response["deleted"] == true
    end
  end

  describe "delete_checkpoint/3" do
    test "deletes checkpoint by run_id and checkpoint_id", %{client: client} do
      {:ok, response} = RestClient.delete_checkpoint(client, "run-123", "ckpt-001")

      assert response["deleted"] == true
    end
  end

  describe "publish_checkpoint/2" do
    test "publishes checkpoint", %{client: client} do
      {:ok, response} =
        RestClient.publish_checkpoint(
          client,
          "tinker://run-123/weights/ckpt-001"
        )

      assert response["published"] == true
    end
  end

  describe "unpublish_checkpoint/2" do
    test "unpublishes checkpoint", %{client: client} do
      {:ok, response} =
        RestClient.unpublish_checkpoint(
          client,
          "tinker://run-123/weights/ckpt-001"
        )

      assert response["unpublished"] == true
    end
  end

  describe "get_training_run/2" do
    test "returns TrainingRun", %{client: client} do
      {:ok, run} = RestClient.get_training_run(client, "run-123")

      assert %TrainingRun{} = run
      assert run.training_run_id == "run-123"
    end
  end

  describe "get_training_run_by_tinker_path/2" do
    test "returns TrainingRun", %{client: client} do
      {:ok, run} =
        RestClient.get_training_run_by_tinker_path(
          client,
          "tinker://run-123/weights/ckpt-001"
        )

      assert %TrainingRun{} = run
    end
  end

  describe "list_training_runs/2" do
    test "returns TrainingRunsResponse", %{client: client} do
      {:ok, response} = RestClient.list_training_runs(client)

      assert %TrainingRunsResponse{} = response
      assert length(response.training_runs) == 1
    end

    test "accepts limit and offset options", %{client: client} do
      {:ok, _response} = RestClient.list_training_runs(client, limit: 50, offset: 10)
    end
  end

  describe "get_sampler/2" do
    test "returns GetSamplerResponse", %{client: client} do
      {:ok, response} = RestClient.get_sampler(client, "session-id:sample:0")

      assert %GetSamplerResponse{} = response
      assert response.base_model == "Qwen/Qwen2.5-7B"
    end
  end

  describe "get_weights_info_by_tinker_path/2" do
    test "returns WeightsInfoResponse", %{client: client} do
      {:ok, response} =
        RestClient.get_weights_info_by_tinker_path(
          client,
          "tinker://run-123/weights/ckpt-001"
        )

      assert %WeightsInfoResponse{} = response
      assert response.is_lora == true
      assert response.lora_rank == 32
    end
  end

  describe "async variants" do
    test "get_session_async returns a Task", %{client: client} do
      task = RestClient.get_session_async(client, "session-123")

      assert %Task{} = task
      {:ok, response} = Task.await(task)
      assert %GetSessionResponse{} = response
    end

    test "list_training_runs_async returns a Task", %{client: client} do
      task = RestClient.list_training_runs_async(client)

      assert %Task{} = task
      {:ok, response} = Task.await(task)
      assert %TrainingRunsResponse{} = response
    end
  end
end
