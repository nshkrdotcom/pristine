defmodule Tinkex.Types.TrainingRunTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{
    TrainingRun,
    TrainingRunsResponse,
    WeightsInfoResponse,
    Cursor,
    Checkpoint
  }

  describe "TrainingRun" do
    test "from_map/1 parses with string keys" do
      map = %{
        "training_run_id" => "run-123",
        "base_model" => "llama-3",
        "model_owner" => "user@example.com",
        "is_lora" => true,
        "lora_rank" => 32,
        "corrupted" => false,
        "last_request_time" => "2024-01-15T10:30:00Z"
      }

      run = TrainingRun.from_map(map)

      assert run.training_run_id == "run-123"
      assert run.base_model == "llama-3"
      assert run.model_owner == "user@example.com"
      assert run.is_lora == true
      assert run.lora_rank == 32
      assert run.corrupted == false
      assert %DateTime{} = run.last_request_time
    end

    test "from_map/1 parses with atom keys" do
      map = %{
        training_run_id: "run-123",
        base_model: "llama-3",
        model_owner: "user@example.com",
        is_lora: false,
        last_request_time: "2024-01-15T10:30:00Z"
      }

      run = TrainingRun.from_map(map)

      assert run.training_run_id == "run-123"
      assert run.base_model == "llama-3"
      assert run.is_lora == false
    end

    test "from_map/1 uses 'id' as fallback for training_run_id" do
      map = %{
        "id" => "run-456",
        "base_model" => "llama-3",
        "model_owner" => "user@example.com",
        "is_lora" => false,
        "last_request_time" => "2024-01-15T10:30:00Z"
      }

      run = TrainingRun.from_map(map)
      assert run.training_run_id == "run-456"
    end

    test "from_map/1 parses boolean from string" do
      map = %{
        "training_run_id" => "run-123",
        "base_model" => "llama-3",
        "model_owner" => "user@example.com",
        "is_lora" => "true",
        "corrupted" => "false",
        "last_request_time" => "2024-01-15T10:30:00Z"
      }

      run = TrainingRun.from_map(map)
      assert run.is_lora == true
      assert run.corrupted == false
    end

    test "from_map/1 defaults corrupted to false" do
      map = %{
        "training_run_id" => "run-123",
        "base_model" => "llama-3",
        "model_owner" => "user@example.com",
        "is_lora" => false,
        "last_request_time" => "2024-01-15T10:30:00Z"
      }

      run = TrainingRun.from_map(map)
      assert run.corrupted == false
    end

    test "from_map/1 parses nested checkpoint" do
      map = %{
        "training_run_id" => "run-123",
        "base_model" => "llama-3",
        "model_owner" => "user@example.com",
        "is_lora" => true,
        "last_request_time" => "2024-01-15T10:30:00Z",
        "last_checkpoint" => %{
          "checkpoint_id" => "ckpt-001",
          "checkpoint_type" => "training",
          "tinker_path" => "tinker://run-123/weights/ckpt-001"
        }
      }

      run = TrainingRun.from_map(map)
      assert %Checkpoint{} = run.last_checkpoint
      assert run.last_checkpoint.checkpoint_id == "ckpt-001"
    end

    test "from_map/1 preserves DateTime values" do
      dt = DateTime.utc_now()

      map = %{
        "training_run_id" => "run-123",
        "base_model" => "llama-3",
        "model_owner" => "user@example.com",
        "is_lora" => false,
        "last_request_time" => dt
      }

      run = TrainingRun.from_map(map)
      assert run.last_request_time == dt
    end

    test "from_map/1 handles user_metadata" do
      map = %{
        "training_run_id" => "run-123",
        "base_model" => "llama-3",
        "model_owner" => "user@example.com",
        "is_lora" => false,
        "last_request_time" => "2024-01-15T10:30:00Z",
        "user_metadata" => %{"experiment" => "test-1"}
      }

      run = TrainingRun.from_map(map)
      assert run.user_metadata == %{"experiment" => "test-1"}
    end
  end

  describe "TrainingRunsResponse" do
    test "from_map/1 parses with string keys" do
      map = %{
        "training_runs" => [
          %{
            "training_run_id" => "run-1",
            "base_model" => "llama-3",
            "model_owner" => "user@example.com",
            "is_lora" => true,
            "last_request_time" => "2024-01-15T10:30:00Z"
          },
          %{
            "training_run_id" => "run-2",
            "base_model" => "llama-3",
            "model_owner" => "user@example.com",
            "is_lora" => false,
            "last_request_time" => "2024-01-15T11:30:00Z"
          }
        ],
        "cursor" => %{
          "offset" => 0,
          "limit" => 10,
          "total_count" => 2
        }
      }

      response = TrainingRunsResponse.from_map(map)

      assert length(response.training_runs) == 2
      assert %TrainingRun{} = hd(response.training_runs)
      assert hd(response.training_runs).training_run_id == "run-1"
      assert %Cursor{} = response.cursor
      assert response.cursor.total_count == 2
    end

    test "from_map/1 parses with atom keys" do
      map = %{
        training_runs: [
          %{
            training_run_id: "run-1",
            base_model: "llama-3",
            model_owner: "user@example.com",
            is_lora: true,
            last_request_time: "2024-01-15T10:30:00Z"
          }
        ],
        cursor: %{offset: 0, limit: 10, total_count: 1}
      }

      response = TrainingRunsResponse.from_map(map)

      assert length(response.training_runs) == 1
      assert response.cursor.total_count == 1
    end

    test "from_map/1 handles nil cursor" do
      map = %{
        "training_runs" => [
          %{
            "training_run_id" => "run-1",
            "base_model" => "llama-3",
            "model_owner" => "user@example.com",
            "is_lora" => false,
            "last_request_time" => "2024-01-15T10:30:00Z"
          }
        ]
      }

      response = TrainingRunsResponse.from_map(map)

      assert length(response.training_runs) == 1
      assert response.cursor == nil
    end
  end

  describe "WeightsInfoResponse" do
    test "from_json/1 parses with string keys" do
      json = %{
        "base_model" => "llama-3",
        "is_lora" => true,
        "lora_rank" => 32
      }

      response = WeightsInfoResponse.from_json(json)

      assert response.base_model == "llama-3"
      assert response.is_lora == true
      assert response.lora_rank == 32
    end

    test "from_json/1 parses with atom keys" do
      json = %{
        base_model: "llama-3",
        is_lora: false,
        lora_rank: nil
      }

      response = WeightsInfoResponse.from_json(json)

      assert response.base_model == "llama-3"
      assert response.is_lora == false
      assert response.lora_rank == nil
    end

    test "from_json/1 handles missing lora_rank" do
      json = %{"base_model" => "llama-3", "is_lora" => false}
      response = WeightsInfoResponse.from_json(json)

      assert response.lora_rank == nil
    end

    test "encodes to JSON with lora_rank" do
      response = %WeightsInfoResponse{
        base_model: "llama-3",
        is_lora: true,
        lora_rank: 32
      }

      json = Jason.encode!(response)
      decoded = Jason.decode!(json)

      assert decoded["base_model"] == "llama-3"
      assert decoded["is_lora"] == true
      assert decoded["lora_rank"] == 32
    end

    test "encodes to JSON without lora_rank" do
      response = %WeightsInfoResponse{
        base_model: "llama-3",
        is_lora: false,
        lora_rank: nil
      }

      json = Jason.encode!(response)
      decoded = Jason.decode!(json)

      assert decoded["base_model"] == "llama-3"
      assert decoded["is_lora"] == false
      refute Map.has_key?(decoded, "lora_rank")
    end
  end
end
