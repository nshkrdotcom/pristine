defmodule Tinkex.Types.SamplingSessionTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.CreateSamplingSessionRequest
  alias Tinkex.Types.CreateSamplingSessionResponse

  describe "CreateSamplingSessionRequest" do
    test "has correct default type" do
      request = %CreateSamplingSessionRequest{
        session_id: "sess_abc",
        sampling_session_seq_id: 1
      }

      assert request.type == "create_sampling_session"
    end

    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        struct!(CreateSamplingSessionRequest, [])
      end

      assert_raise ArgumentError, fn ->
        struct!(CreateSamplingSessionRequest, session_id: "sess")
      end

      assert_raise ArgumentError, fn ->
        struct!(CreateSamplingSessionRequest, sampling_session_seq_id: 1)
      end
    end

    test "accepts session_id and sampling_session_seq_id" do
      request = %CreateSamplingSessionRequest{
        session_id: "sess_xyz",
        sampling_session_seq_id: 42
      }

      assert request.session_id == "sess_xyz"
      assert request.sampling_session_seq_id == 42
    end

    test "accepts optional base_model" do
      request = %CreateSamplingSessionRequest{
        session_id: "sess_abc",
        sampling_session_seq_id: 1,
        base_model: "kimi-k2"
      }

      assert request.base_model == "kimi-k2"
    end

    test "accepts optional model_path" do
      request = %CreateSamplingSessionRequest{
        session_id: "sess_abc",
        sampling_session_seq_id: 1,
        model_path: "tinker://user/run/checkpoint"
      }

      assert request.model_path == "tinker://user/run/checkpoint"
    end

    test "base_model and model_path default to nil" do
      request = %CreateSamplingSessionRequest{
        session_id: "sess_abc",
        sampling_session_seq_id: 1
      }

      assert request.base_model == nil
      assert request.model_path == nil
    end

    test "encodes to JSON correctly" do
      request = %CreateSamplingSessionRequest{
        session_id: "sess_test",
        sampling_session_seq_id: 5,
        base_model: "llama-3",
        model_path: nil
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["session_id"] == "sess_test"
      assert decoded["sampling_session_seq_id"] == 5
      assert decoded["base_model"] == "llama-3"
      assert decoded["model_path"] == nil
      assert decoded["type"] == "create_sampling_session"
    end

    test "encodes nil optional fields" do
      request = %CreateSamplingSessionRequest{
        session_id: "sess_minimal",
        sampling_session_seq_id: 0
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["base_model"] == nil
      assert decoded["model_path"] == nil
    end
  end

  describe "CreateSamplingSessionResponse" do
    test "enforces sampling_session_id" do
      assert_raise ArgumentError, fn ->
        struct!(CreateSamplingSessionResponse, [])
      end
    end

    test "accepts sampling_session_id" do
      response = %CreateSamplingSessionResponse{sampling_session_id: "samp_sess_123"}
      assert response.sampling_session_id == "samp_sess_123"
    end

    test "from_json/1 parses string-keyed map" do
      json = %{"sampling_session_id" => "samp_parsed"}
      response = CreateSamplingSessionResponse.from_json(json)

      assert response.sampling_session_id == "samp_parsed"
    end

    test "from_json/1 handles typical API response" do
      json = %{
        "sampling_session_id" => "samp_abc123",
        "extra_field" => "ignored"
      }

      response = CreateSamplingSessionResponse.from_json(json)
      assert response.sampling_session_id == "samp_abc123"
    end
  end
end
