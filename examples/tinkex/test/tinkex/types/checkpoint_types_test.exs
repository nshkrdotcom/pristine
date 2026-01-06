defmodule Tinkex.Types.CheckpointTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{
    Cursor,
    ParsedCheckpointTinkerPath,
    Checkpoint,
    CheckpointsListResponse
  }

  describe "Cursor" do
    test "from_map/1 returns nil for nil input" do
      assert Cursor.from_map(nil) == nil
    end

    test "from_map/1 parses with string keys" do
      map = %{"offset" => 10, "limit" => 50, "total_count" => 100}
      cursor = Cursor.from_map(map)

      assert cursor.offset == 10
      assert cursor.limit == 50
      assert cursor.total_count == 100
    end

    test "from_map/1 parses with atom keys" do
      map = %{offset: 10, limit: 50, total_count: 100}
      cursor = Cursor.from_map(map)

      assert cursor.offset == 10
      assert cursor.limit == 50
      assert cursor.total_count == 100
    end

    test "from_map/1 coerces string values to integers" do
      map = %{"offset" => "10", "limit" => "50", "total_count" => "100"}
      cursor = Cursor.from_map(map)

      assert cursor.offset == 10
      assert cursor.limit == 50
      assert cursor.total_count == 100
    end

    test "from_map/1 defaults missing values to 0" do
      map = %{}
      cursor = Cursor.from_map(map)

      assert cursor.offset == 0
      assert cursor.limit == 0
      assert cursor.total_count == 0
    end
  end

  describe "ParsedCheckpointTinkerPath" do
    test "from_tinker_path/1 parses weights path" do
      {:ok, parsed} =
        ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/weights/ckpt-001")

      assert parsed.tinker_path == "tinker://run-123/weights/ckpt-001"
      assert parsed.training_run_id == "run-123"
      assert parsed.checkpoint_type == "training"
      assert parsed.checkpoint_id == "ckpt-001"
    end

    test "from_tinker_path/1 parses sampler_weights path" do
      {:ok, parsed} =
        ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-456/sampler_weights/ckpt-002")

      assert parsed.tinker_path == "tinker://run-456/sampler_weights/ckpt-002"
      assert parsed.training_run_id == "run-456"
      assert parsed.checkpoint_type == "sampler"
      assert parsed.checkpoint_id == "ckpt-002"
    end

    test "from_tinker_path/1 returns error for invalid prefix" do
      {:error, error} = ParsedCheckpointTinkerPath.from_tinker_path("http://example.com")
      assert error.type == :validation_error
      assert error.message =~ "Invalid tinker path format"
    end

    test "from_tinker_path/1 returns error for missing components" do
      {:error, error} = ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/weights")
      assert error.type == :validation_error
    end

    test "from_tinker_path/1 returns error for unknown type" do
      {:error, error} =
        ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/unknown/ckpt-001")

      assert error.type == :validation_error
    end

    test "from_tinker_path/1 returns error for empty components" do
      {:error, error} = ParsedCheckpointTinkerPath.from_tinker_path("tinker:///weights/ckpt-001")
      assert error.type == :validation_error
    end

    test "checkpoint_segment/1 returns weights segment for training type" do
      {:ok, parsed} =
        ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/weights/ckpt-001")

      assert ParsedCheckpointTinkerPath.checkpoint_segment(parsed) == "weights/ckpt-001"
    end

    test "checkpoint_segment/1 returns sampler_weights segment for sampler type" do
      {:ok, parsed} =
        ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/sampler_weights/ckpt-002")

      assert ParsedCheckpointTinkerPath.checkpoint_segment(parsed) == "sampler_weights/ckpt-002"
    end
  end

  describe "Checkpoint" do
    test "from_map/1 parses with string keys" do
      map = %{
        "checkpoint_id" => "ckpt-001",
        "checkpoint_type" => "training",
        "tinker_path" => "tinker://run-123/weights/ckpt-001",
        "training_run_id" => "run-123",
        "size_bytes" => 1024,
        "public" => true,
        "time" => "2024-01-15T10:30:00Z"
      }

      checkpoint = Checkpoint.from_map(map)

      assert checkpoint.checkpoint_id == "ckpt-001"
      assert checkpoint.checkpoint_type == "training"
      assert checkpoint.tinker_path == "tinker://run-123/weights/ckpt-001"
      assert checkpoint.training_run_id == "run-123"
      assert checkpoint.size_bytes == 1024
      assert checkpoint.public == true
      assert %DateTime{} = checkpoint.time
    end

    test "from_map/1 parses with atom keys" do
      map = %{
        checkpoint_id: "ckpt-001",
        checkpoint_type: "training",
        tinker_path: "tinker://run-123/weights/ckpt-001",
        training_run_id: "run-123",
        size_bytes: 1024,
        public: true,
        time: "2024-01-15T10:30:00Z"
      }

      checkpoint = Checkpoint.from_map(map)

      assert checkpoint.checkpoint_id == "ckpt-001"
      assert checkpoint.checkpoint_type == "training"
      assert checkpoint.training_run_id == "run-123"
    end

    test "from_map/1 derives training_run_id from tinker_path" do
      map = %{
        "checkpoint_id" => "ckpt-001",
        "checkpoint_type" => "training",
        "tinker_path" => "tinker://derived-run/weights/ckpt-001"
      }

      checkpoint = Checkpoint.from_map(map)
      assert checkpoint.training_run_id == "derived-run"
    end

    test "from_map/1 prefers explicit training_run_id over derived" do
      map = %{
        "checkpoint_id" => "ckpt-001",
        "checkpoint_type" => "training",
        "tinker_path" => "tinker://derived-run/weights/ckpt-001",
        "training_run_id" => "explicit-run"
      }

      checkpoint = Checkpoint.from_map(map)
      assert checkpoint.training_run_id == "explicit-run"
    end

    test "from_map/1 defaults public to false" do
      map = %{"checkpoint_id" => "ckpt-001"}
      checkpoint = Checkpoint.from_map(map)
      assert checkpoint.public == false
    end

    test "from_map/1 handles DateTime values" do
      dt = DateTime.utc_now()

      map = %{
        "checkpoint_id" => "ckpt-001",
        "time" => dt
      }

      checkpoint = Checkpoint.from_map(map)
      assert checkpoint.time == dt
    end

    test "from_map/1 preserves unparseable time strings" do
      map = %{
        "checkpoint_id" => "ckpt-001",
        "time" => "not-a-date"
      }

      checkpoint = Checkpoint.from_map(map)
      assert checkpoint.time == "not-a-date"
    end

    test "from_map/1 handles nil time" do
      map = %{"checkpoint_id" => "ckpt-001", "time" => nil}
      checkpoint = Checkpoint.from_map(map)
      assert checkpoint.time == nil
    end

    test "training_run_from_path/1 returns nil for nil" do
      assert Checkpoint.training_run_from_path(nil) == nil
    end

    test "training_run_from_path/1 extracts run id" do
      assert Checkpoint.training_run_from_path("tinker://run-123/weights/ckpt-001") == "run-123"
    end

    test "training_run_from_path/1 returns nil for invalid path" do
      assert Checkpoint.training_run_from_path("invalid") == nil
    end
  end

  describe "CheckpointsListResponse" do
    test "from_map/1 parses with string keys" do
      map = %{
        "checkpoints" => [
          %{
            "checkpoint_id" => "ckpt-001",
            "checkpoint_type" => "training",
            "tinker_path" => "tinker://run-123/weights/ckpt-001"
          },
          %{
            "checkpoint_id" => "ckpt-002",
            "checkpoint_type" => "sampler",
            "tinker_path" => "tinker://run-123/sampler_weights/ckpt-002"
          }
        ],
        "cursor" => %{
          "offset" => 0,
          "limit" => 10,
          "total_count" => 2
        }
      }

      response = CheckpointsListResponse.from_map(map)

      assert length(response.checkpoints) == 2
      assert %Checkpoint{} = hd(response.checkpoints)
      assert hd(response.checkpoints).checkpoint_id == "ckpt-001"
      assert %Cursor{} = response.cursor
      assert response.cursor.total_count == 2
    end

    test "from_map/1 parses with atom keys" do
      map = %{
        checkpoints: [
          %{checkpoint_id: "ckpt-001", checkpoint_type: "training"}
        ],
        cursor: %{offset: 0, limit: 10, total_count: 1}
      }

      response = CheckpointsListResponse.from_map(map)

      assert length(response.checkpoints) == 1
      assert response.cursor.total_count == 1
    end

    test "from_map/1 defaults to empty list for missing checkpoints" do
      map = %{}
      response = CheckpointsListResponse.from_map(map)

      assert response.checkpoints == []
      assert response.cursor == nil
    end

    test "from_map/1 handles nil cursor" do
      map = %{
        "checkpoints" => [
          %{"checkpoint_id" => "ckpt-001"}
        ],
        "cursor" => nil
      }

      response = CheckpointsListResponse.from_map(map)

      assert length(response.checkpoints) == 1
      assert response.cursor == nil
    end
  end
end
