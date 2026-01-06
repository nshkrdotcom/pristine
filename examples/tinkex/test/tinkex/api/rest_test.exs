defmodule Tinkex.API.RestTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Rest
  alias Tinkex.Error
  alias Tinkex.Types.{TrainingRun, TrainingRunsResponse, GetSamplerResponse, WeightsInfoResponse}

  defmodule MockClient do
    @behaviour Tinkex.HTTPClient

    @impl true
    def get(path, opts) do
      test_pid = opts[:test_pid] || self()
      send(test_pid, {:mock_get, path, opts})
      mock_response(path, opts)
    end

    @impl true
    def post(path, body, opts) do
      test_pid = opts[:test_pid] || self()
      send(test_pid, {:mock_post, path, body, opts})
      mock_response(path, opts)
    end

    @impl true
    def delete(path, opts) do
      test_pid = opts[:test_pid] || self()
      send(test_pid, {:mock_delete, path, opts})
      mock_response(path, opts)
    end

    defp mock_response(path, opts) do
      case opts[:mock_response] do
        nil -> default_response(path)
        response -> response
      end
    end

    defp default_response(path) do
      cond do
        # Checkpoint archive URL (must match before /checkpoints)
        String.contains?(path, "/checkpoints") and String.contains?(path, "/archive") ->
          {:ok, %{"url" => "https://storage.example.com/checkpoint.tar.gz"}}

        # List user checkpoints (with query string)
        String.contains?(path, "/checkpoints?") ->
          {:ok,
           %{
             "checkpoints" => [
               %{
                 "checkpoint_id" => "checkpoint-001",
                 "checkpoint_type" => "weights",
                 "tinker_path" => "tinker://run-123/weights/checkpoint-001",
                 "public" => false
               }
             ],
             "cursor" => %{"offset" => 0, "limit" => 100, "total_count" => 1}
           }}

        # List/delete checkpoints for a training run
        String.contains?(path, "/training_runs/") and String.contains?(path, "/checkpoints") ->
          {:ok,
           %{
             "checkpoints" => [
               %{
                 "checkpoint_id" => "checkpoint-001",
                 "checkpoint_type" => "weights",
                 "tinker_path" => "tinker://run-123/weights/checkpoint-001",
                 "public" => false
               }
             ]
           }}

        # List training runs (with query string)
        String.contains?(path, "/training_runs?") ->
          {:ok,
           %{
             "training_runs" => [
               %{
                 "training_run_id" => "run-123",
                 "base_model" => "Qwen/Qwen2.5-7B",
                 "model_owner" => "user-1",
                 "is_lora" => true,
                 "lora_rank" => 32,
                 "corrupted" => false,
                 "last_request_time" => "2024-01-01T00:00:00Z"
               }
             ],
             "cursor" => %{"offset" => 0, "limit" => 20, "total_count" => 1}
           }}

        # Get specific training run
        String.contains?(path, "/training_runs/") ->
          {:ok,
           %{
             "training_run_id" => "run-123",
             "base_model" => "Qwen/Qwen2.5-7B",
             "model_owner" => "user-1",
             "is_lora" => true,
             "lora_rank" => 32,
             "corrupted" => false,
             "last_request_time" => "2024-01-01T00:00:00Z"
           }}

        # Get specific session
        String.contains?(path, "/sessions/") ->
          {:ok,
           %{
             "training_run_ids" => ["run-123"],
             "sampler_ids" => ["sampler-1"]
           }}

        # List sessions
        String.contains?(path, "/sessions?") ->
          {:ok, %{"sessions" => ["session-1", "session-2"]}}

        # Get sampler
        String.contains?(path, "/samplers/") ->
          {:ok,
           %{
             "sampler_id" => "session-id:sample:0",
             "base_model" => "Qwen/Qwen2.5-7B",
             "model_path" => "tinker://run-123/weights/checkpoint-001"
           }}

        # Get weights info
        String.contains?(path, "/weights_info") ->
          {:ok,
           %{
             "base_model" => "Qwen/Qwen2.5-7B",
             "is_lora" => true,
             "lora_rank" => 32
           }}

        true ->
          {:ok, %{}}
      end
    end
  end

  setup do
    config = %Tinkex.Config{
      base_url: "https://example.com",
      api_key: "tml-test-key",
      timeout: 60_000,
      max_retries: 3,
      http_client: MockClient
    }

    {:ok, config: config}
  end

  describe "list_training_runs/3" do
    test "lists training runs with default pagination", %{config: config} do
      {:ok, response} = Rest.list_training_runs(config)

      assert %TrainingRunsResponse{} = response
      assert length(response.training_runs) == 1
      assert hd(response.training_runs).training_run_id == "run-123"

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/training_runs?limit=20&offset=0"
    end

    test "lists training runs with custom pagination", %{config: config} do
      {:ok, _response} = Rest.list_training_runs(config, 50, 10)

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/training_runs?limit=50&offset=10"
    end

    test "returns error on failure", %{config: config} do
      config = %{config | http_client: MockClient}
      error = Error.new(:api_status, "Server error", status: 500)

      {:error, ^error} =
        Rest.list_training_runs(config, 20, 0,
          mock_response: {:error, error},
          http_client: MockClient
        )
    end
  end

  describe "get_training_run/2" do
    test "gets training run by ID", %{config: config} do
      {:ok, run} = Rest.get_training_run(config, "run-123")

      assert %TrainingRun{} = run
      assert run.training_run_id == "run-123"
      assert run.base_model == "Qwen/Qwen2.5-7B"
      assert run.is_lora == true
      assert run.lora_rank == 32

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/training_runs/run-123"
    end
  end

  describe "get_session/2" do
    test "gets session by ID", %{config: config} do
      {:ok, session} = Rest.get_session(config, "session-abc")

      assert session["training_run_ids"] == ["run-123"]
      assert session["sampler_ids"] == ["sampler-1"]

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/sessions/session-abc"
    end
  end

  describe "list_sessions/3" do
    test "lists sessions with default pagination", %{config: config} do
      {:ok, response} = Rest.list_sessions(config)

      assert response["sessions"] == ["session-1", "session-2"]

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/sessions?limit=20&offset=0"
    end

    test "lists sessions with custom pagination", %{config: config} do
      {:ok, _response} = Rest.list_sessions(config, 50, 10)

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/sessions?limit=50&offset=10"
    end
  end

  describe "list_checkpoints/2" do
    test "lists checkpoints for training run", %{config: config} do
      {:ok, response} = Rest.list_checkpoints(config, "run-123")

      assert is_list(response["checkpoints"])

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/training_runs/run-123/checkpoints"
    end
  end

  describe "list_user_checkpoints/3" do
    test "lists user checkpoints with default pagination", %{config: config} do
      {:ok, _response} = Rest.list_user_checkpoints(config)

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/checkpoints?limit=100&offset=0"
    end

    test "lists user checkpoints with custom pagination", %{config: config} do
      {:ok, _response} = Rest.list_user_checkpoints(config, 50, 25)

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/checkpoints?limit=50&offset=25"
    end
  end

  describe "get_checkpoint_archive_url/2" do
    test "gets archive URL by tinker path", %{config: config} do
      {:ok, response} =
        Rest.get_checkpoint_archive_url(config, "tinker://run-123/weights/checkpoint-001")

      assert response["url"] =~ "storage.example.com"

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/training_runs/run-123/checkpoints/weights%2Fcheckpoint-001/archive"
    end

    test "returns error for invalid tinker path", %{config: config} do
      {:error, %Error{}} = Rest.get_checkpoint_archive_url(config, "invalid-path")
    end
  end

  describe "get_checkpoint_archive_url/3" do
    test "gets archive URL by run_id and checkpoint_id", %{config: config} do
      {:ok, response} = Rest.get_checkpoint_archive_url(config, "run-123", "checkpoint-001")

      assert response["url"] =~ "storage.example.com"

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/training_runs/run-123/checkpoints/checkpoint-001/archive"
    end
  end

  describe "delete_checkpoint/2" do
    test "deletes checkpoint by tinker path", %{config: config} do
      {:ok, _response} =
        Rest.delete_checkpoint(config, "tinker://run-123/weights/checkpoint-001")

      assert_receive {:mock_delete, path, _opts}
      assert path == "/api/v1/training_runs/run-123/checkpoints/weights%2Fcheckpoint-001"
    end

    test "returns error for invalid tinker path", %{config: config} do
      {:error, %Error{}} = Rest.delete_checkpoint(config, "invalid-path")
    end
  end

  describe "delete_checkpoint/3" do
    test "deletes checkpoint by run_id and checkpoint_id", %{config: config} do
      {:ok, _response} = Rest.delete_checkpoint(config, "run-123", "checkpoint-001")

      assert_receive {:mock_delete, path, _opts}
      assert path == "/api/v1/training_runs/run-123/checkpoints/checkpoint-001"
    end
  end

  describe "get_sampler/2" do
    test "gets sampler info", %{config: config} do
      {:ok, response} = Rest.get_sampler(config, "session-id:sample:0")

      assert %GetSamplerResponse{} = response
      assert response.sampler_id == "session-id:sample:0"
      assert response.base_model == "Qwen/Qwen2.5-7B"

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/samplers/session-id%3Asample%3A0"
    end
  end

  describe "get_weights_info_by_tinker_path/2" do
    test "gets weights info", %{config: config} do
      {:ok, response} =
        Rest.get_weights_info_by_tinker_path(config, "tinker://run-123/weights/checkpoint-001")

      assert %WeightsInfoResponse{} = response
      assert response.base_model == "Qwen/Qwen2.5-7B"
      assert response.is_lora == true
      assert response.lora_rank == 32

      assert_receive {:mock_post, path, body, _opts}
      assert path == "/api/v1/weights_info"
      assert body["tinker_path"] == "tinker://run-123/weights/checkpoint-001"
    end
  end

  describe "get_training_run_by_tinker_path/2" do
    test "gets training run by tinker path", %{config: config} do
      {:ok, run} =
        Rest.get_training_run_by_tinker_path(config, "tinker://run-123/weights/checkpoint-001")

      assert %TrainingRun{} = run
      assert run.training_run_id == "run-123"

      assert_receive {:mock_get, path, _opts}
      assert path == "/api/v1/training_runs/run-123"
    end

    test "returns error for invalid tinker path", %{config: config} do
      {:error, %Error{}} = Rest.get_training_run_by_tinker_path(config, "invalid-path")
    end
  end

  describe "publish_checkpoint/2" do
    test "publishes checkpoint", %{config: config} do
      {:ok, _response} =
        Rest.publish_checkpoint(config, "tinker://run-123/weights/checkpoint-001")

      assert_receive {:mock_post, path, _body, _opts}
      assert path == "/api/v1/training_runs/run-123/checkpoints/weights%2Fcheckpoint-001/publish"
    end
  end

  describe "unpublish_checkpoint/2" do
    test "unpublishes checkpoint", %{config: config} do
      {:ok, _response} =
        Rest.unpublish_checkpoint(config, "tinker://run-123/weights/checkpoint-001")

      assert_receive {:mock_delete, path, _opts}
      assert path == "/api/v1/training_runs/run-123/checkpoints/weights%2Fcheckpoint-001/publish"
    end
  end
end
