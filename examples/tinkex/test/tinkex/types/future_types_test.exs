defmodule Tinkex.Types.FutureTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{
    QueueState,
    FutureRetrieveRequest,
    FuturePendingResponse,
    FutureCompletedResponse,
    FutureFailedResponse,
    FutureRetrieveResponse,
    TryAgainResponse
  }

  describe "QueueState" do
    test "parse/1 parses active" do
      assert QueueState.parse("active") == :active
      assert QueueState.parse("ACTIVE") == :active
      assert QueueState.parse("  active  ") == :active
    end

    test "parse/1 parses paused_rate_limit" do
      assert QueueState.parse("paused_rate_limit") == :paused_rate_limit
      assert QueueState.parse("PAUSED_RATE_LIMIT") == :paused_rate_limit
    end

    test "parse/1 parses paused_capacity" do
      assert QueueState.parse("paused_capacity") == :paused_capacity
    end

    test "parse/1 returns unknown for invalid values" do
      assert QueueState.parse("invalid") == :unknown
      assert QueueState.parse("") == :unknown
      assert QueueState.parse(nil) == :unknown
    end

    test "to_string/1 converts atoms" do
      assert QueueState.to_string(:active) == "active"
      assert QueueState.to_string(:paused_rate_limit) == "paused_rate_limit"
      assert QueueState.to_string(:paused_capacity) == "paused_capacity"
      assert QueueState.to_string(:unknown) == "unknown"
    end
  end

  describe "FutureRetrieveRequest" do
    test "new/1 creates request" do
      request = FutureRetrieveRequest.new("req-123")
      assert request.request_id == "req-123"
    end

    test "to_json/1 converts to map" do
      request = FutureRetrieveRequest.new("req-123")
      assert FutureRetrieveRequest.to_json(request) == %{"request_id" => "req-123"}
    end

    test "from_json/1 parses with string keys" do
      json = %{"request_id" => "req-123"}
      request = FutureRetrieveRequest.from_json(json)
      assert request.request_id == "req-123"
    end

    test "from_json/1 parses with atom keys" do
      json = %{request_id: "req-123"}
      request = FutureRetrieveRequest.from_json(json)
      assert request.request_id == "req-123"
    end
  end

  describe "FuturePendingResponse" do
    test "creates with default status" do
      response = %FuturePendingResponse{}
      assert response.status == "pending"
    end
  end

  describe "FutureCompletedResponse" do
    test "creates with status and result" do
      response = %FutureCompletedResponse{
        status: "completed",
        result: %{"data" => "value"}
      }

      assert response.status == "completed"
      assert response.result == %{"data" => "value"}
    end
  end

  describe "FutureFailedResponse" do
    test "creates with status and error" do
      response = %FutureFailedResponse{
        status: "failed",
        error: %{"message" => "Something went wrong"}
      }

      assert response.status == "failed"
      assert response.error == %{"message" => "Something went wrong"}
    end
  end

  describe "FutureRetrieveResponse" do
    test "from_json/1 parses pending with string keys" do
      json = %{"status" => "pending"}
      response = FutureRetrieveResponse.from_json(json)
      assert %FuturePendingResponse{} = response
      assert response.status == "pending"
    end

    test "from_json/1 parses completed with string keys" do
      json = %{"status" => "completed", "result" => %{"data" => "value"}}
      response = FutureRetrieveResponse.from_json(json)
      assert %FutureCompletedResponse{} = response
      assert response.status == "completed"
      assert response.result == %{"data" => "value"}
    end

    test "from_json/1 parses failed with string keys" do
      json = %{"status" => "failed", "error" => %{"message" => "Error"}}
      response = FutureRetrieveResponse.from_json(json)
      assert %FutureFailedResponse{} = response
      assert response.status == "failed"
      assert response.error == %{"message" => "Error"}
    end

    test "from_json/1 parses with atom keys" do
      json = %{status: "pending"}
      response = FutureRetrieveResponse.from_json(json)
      assert %FuturePendingResponse{} = response
    end
  end

  describe "TryAgainResponse" do
    test "from_map/1 parses with string keys" do
      map = %{
        "type" => "try_again",
        "request_id" => "req-123",
        "queue_state" => "paused_rate_limit",
        "retry_after_ms" => 5000,
        "queue_state_reason" => "Rate limit exceeded"
      }

      response = TryAgainResponse.from_map(map)

      assert response.type == "try_again"
      assert response.request_id == "req-123"
      assert response.queue_state == :paused_rate_limit
      assert response.retry_after_ms == 5000
      assert response.queue_state_reason == "Rate limit exceeded"
    end

    test "from_map/1 parses with atom keys" do
      map = %{
        type: "try_again",
        request_id: "req-123",
        queue_state: "active"
      }

      response = TryAgainResponse.from_map(map)

      assert response.type == "try_again"
      assert response.request_id == "req-123"
      assert response.queue_state == :active
      assert response.retry_after_ms == nil
      assert response.queue_state_reason == nil
    end

    test "from_map/1 raises for invalid type" do
      map = %{"type" => "invalid", "request_id" => "req-123", "queue_state" => "active"}

      assert_raise ArgumentError, ~r/only accepts type "try_again"/, fn ->
        TryAgainResponse.from_map(map)
      end
    end

    test "from_map/1 raises for missing required fields" do
      assert_raise ArgumentError, ~r/missing required field/, fn ->
        TryAgainResponse.from_map(%{"type" => "try_again"})
      end
    end

    test "from_map/1 raises for invalid retry_after_ms" do
      map = %{
        "type" => "try_again",
        "request_id" => "req-123",
        "queue_state" => "active",
        "retry_after_ms" => -1
      }

      assert_raise ArgumentError, ~r/non-negative integer/, fn ->
        TryAgainResponse.from_map(map)
      end
    end
  end
end
