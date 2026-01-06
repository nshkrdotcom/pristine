defmodule Tinkex.Types.SessionTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.CreateSessionRequest
  alias Tinkex.Types.CreateSessionResponse
  alias Tinkex.Types.SessionHeartbeatRequest
  alias Tinkex.Types.SessionHeartbeatResponse

  describe "CreateSessionRequest" do
    test "has correct default type" do
      request = %CreateSessionRequest{tags: ["test"], sdk_version: "0.1.0"}
      assert request.type == "create_session"
    end

    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        struct!(CreateSessionRequest, [])
      end
    end

    test "accepts tags and sdk_version" do
      request = %CreateSessionRequest{tags: ["tag1", "tag2"], sdk_version: "1.0.0"}
      assert request.tags == ["tag1", "tag2"]
      assert request.sdk_version == "1.0.0"
    end

    test "accepts optional user_metadata" do
      metadata = %{"key" => "value", "nested" => %{"a" => 1}}

      request = %CreateSessionRequest{
        tags: [],
        sdk_version: "1.0.0",
        user_metadata: metadata
      }

      assert request.user_metadata == metadata
    end

    test "user_metadata defaults to nil" do
      request = %CreateSessionRequest{tags: [], sdk_version: "1.0.0"}
      assert request.user_metadata == nil
    end

    test "encodes to JSON correctly" do
      request = %CreateSessionRequest{
        tags: ["prod", "ml"],
        sdk_version: "0.3.0",
        user_metadata: %{"run_id" => "abc123"}
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["tags"] == ["prod", "ml"]
      assert decoded["sdk_version"] == "0.3.0"
      assert decoded["user_metadata"] == %{"run_id" => "abc123"}
      assert decoded["type"] == "create_session"
    end

    test "encodes nil user_metadata as null" do
      request = %CreateSessionRequest{tags: [], sdk_version: "1.0.0"}
      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["user_metadata"] == nil
    end
  end

  describe "CreateSessionResponse" do
    test "enforces session_id" do
      assert_raise ArgumentError, fn ->
        struct!(CreateSessionResponse, [])
      end
    end

    test "accepts session_id" do
      response = %CreateSessionResponse{session_id: "sess_abc123"}
      assert response.session_id == "sess_abc123"
    end

    test "message fields default to nil" do
      response = %CreateSessionResponse{session_id: "sess_abc"}
      assert response.info_message == nil
      assert response.warning_message == nil
      assert response.error_message == nil
    end

    test "accepts all message fields" do
      response = %CreateSessionResponse{
        session_id: "sess_xyz",
        info_message: "Session created",
        warning_message: "Rate limit approaching",
        error_message: nil
      }

      assert response.info_message == "Session created"
      assert response.warning_message == "Rate limit approaching"
    end

    test "from_json/1 parses string-keyed map" do
      json = %{
        "session_id" => "sess_parsed",
        "info_message" => "Info here",
        "warning_message" => nil,
        "error_message" => "Something wrong"
      }

      response = CreateSessionResponse.from_json(json)

      assert response.session_id == "sess_parsed"
      assert response.info_message == "Info here"
      assert response.warning_message == nil
      assert response.error_message == "Something wrong"
    end

    test "from_json/1 handles missing optional fields" do
      json = %{"session_id" => "sess_minimal"}
      response = CreateSessionResponse.from_json(json)

      assert response.session_id == "sess_minimal"
      assert response.info_message == nil
    end
  end

  describe "SessionHeartbeatRequest" do
    test "has correct default type" do
      request = %SessionHeartbeatRequest{session_id: "sess_abc"}
      assert request.type == "session_heartbeat"
    end

    test "enforces session_id" do
      assert_raise ArgumentError, fn ->
        struct!(SessionHeartbeatRequest, [])
      end
    end

    test "new/1 creates with session_id" do
      request = SessionHeartbeatRequest.new("sess_test123")
      assert request.session_id == "sess_test123"
      assert request.type == "session_heartbeat"
    end

    test "to_json/1 returns correct map" do
      request = SessionHeartbeatRequest.new("sess_heartbeat")
      json = SessionHeartbeatRequest.to_json(request)

      assert json == %{"session_id" => "sess_heartbeat", "type" => "session_heartbeat"}
    end

    test "from_json/1 parses string-keyed map" do
      json = %{"session_id" => "sess_from_json", "type" => "session_heartbeat"}
      request = SessionHeartbeatRequest.from_json(json)

      assert request.session_id == "sess_from_json"
      assert request.type == "session_heartbeat"
    end

    test "from_json/1 parses atom-keyed map" do
      json = %{session_id: "sess_atom_keys"}
      request = SessionHeartbeatRequest.from_json(json)

      assert request.session_id == "sess_atom_keys"
    end
  end

  describe "SessionHeartbeatResponse" do
    test "has correct default type" do
      response = %SessionHeartbeatResponse{}
      assert response.type == "session_heartbeat"
    end

    test "new/0 creates default response" do
      response = SessionHeartbeatResponse.new()
      assert response.type == "session_heartbeat"
    end

    test "from_json/1 parses string-keyed map" do
      json = %{"type" => "session_heartbeat"}
      response = SessionHeartbeatResponse.from_json(json)

      assert response.type == "session_heartbeat"
    end

    test "from_json/1 parses atom-keyed map" do
      json = %{type: "session_heartbeat"}
      response = SessionHeartbeatResponse.from_json(json)

      assert response.type == "session_heartbeat"
    end

    test "from_json/1 handles unexpected input gracefully" do
      json = %{"unexpected" => "field"}
      response = SessionHeartbeatResponse.from_json(json)

      assert response.type == "session_heartbeat"
    end
  end
end
