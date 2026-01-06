defmodule Tinkex.Types.SamplingTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{
    StopReason,
    SamplingParams,
    SampledSequence,
    SampleRequest,
    SampleResponse,
    SampleStreamChunk,
    ModelInput
  }

  describe "StopReason" do
    test "parse/1 parses length" do
      assert StopReason.parse("length") == :length
    end

    test "parse/1 parses stop" do
      assert StopReason.parse("stop") == :stop
    end

    test "parse/1 returns nil for unknown" do
      assert StopReason.parse("unknown") == nil
      assert StopReason.parse("") == nil
      assert StopReason.parse(nil) == nil
    end

    test "to_string/1 converts length" do
      assert StopReason.to_string(:length) == "length"
    end

    test "to_string/1 converts stop" do
      assert StopReason.to_string(:stop) == "stop"
    end
  end

  describe "SamplingParams" do
    test "creates struct with defaults" do
      params = %SamplingParams{}

      assert params.temperature == 1.0
      assert params.top_k == -1
      assert params.top_p == 1.0
      assert params.max_tokens == nil
      assert params.seed == nil
      assert params.stop == nil
    end

    test "creates struct with custom values" do
      params = %SamplingParams{
        max_tokens: 100,
        seed: 42,
        stop: ["<|end|>"],
        temperature: 0.7,
        top_k: 50,
        top_p: 0.9
      }

      assert params.max_tokens == 100
      assert params.seed == 42
      assert params.stop == ["<|end|>"]
      assert params.temperature == 0.7
      assert params.top_k == 50
      assert params.top_p == 0.9
    end

    test "encodes to JSON" do
      params = %SamplingParams{
        max_tokens: 100,
        temperature: 0.7
      }

      json = Jason.encode!(params)
      decoded = Jason.decode!(json)

      assert decoded["max_tokens"] == 100
      assert decoded["temperature"] == 0.7
      assert decoded["top_k"] == -1
      assert decoded["top_p"] == 1.0
    end

    test "encodes nil fields as null" do
      params = %SamplingParams{}
      json = Jason.encode!(params)
      decoded = Jason.decode!(json)

      assert decoded["max_tokens"] == nil
      assert decoded["seed"] == nil
    end
  end

  describe "SampledSequence" do
    test "from_json/1 parses with string keys" do
      json = %{
        "tokens" => [1, 2, 3, 4, 5],
        "logprobs" => [-0.1, -0.2, -0.3, -0.4, -0.5],
        "stop_reason" => "length"
      }

      sequence = SampledSequence.from_json(json)

      assert sequence.tokens == [1, 2, 3, 4, 5]
      assert sequence.logprobs == [-0.1, -0.2, -0.3, -0.4, -0.5]
      assert sequence.stop_reason == :length
    end

    test "from_json/1 parses with atom keys" do
      json = %{
        tokens: [1, 2, 3],
        logprobs: [-0.1, -0.2, -0.3],
        stop_reason: "stop"
      }

      sequence = SampledSequence.from_json(json)

      assert sequence.tokens == [1, 2, 3]
      assert sequence.stop_reason == :stop
    end

    test "from_json/1 handles missing optional fields" do
      json = %{"tokens" => [1, 2, 3]}

      sequence = SampledSequence.from_json(json)

      assert sequence.tokens == [1, 2, 3]
      assert sequence.logprobs == nil
      assert sequence.stop_reason == nil
    end

    test "enforces tokens" do
      assert_raise ArgumentError, fn ->
        struct!(SampledSequence, [])
      end
    end
  end

  describe "SampleRequest" do
    test "creates struct with required fields" do
      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{max_tokens: 100}

      request = %SampleRequest{prompt: prompt, sampling_params: params}

      assert request.prompt == prompt
      assert request.sampling_params == params
      assert request.num_samples == 1
      assert request.type == "sample"
    end

    test "creates struct with session ID" do
      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{}

      request = %SampleRequest{
        prompt: prompt,
        sampling_params: params,
        sampling_session_id: "session-123",
        seq_id: 5
      }

      assert request.sampling_session_id == "session-123"
      assert request.seq_id == 5
    end

    test "creates struct with model path" do
      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{}

      request = %SampleRequest{
        prompt: prompt,
        sampling_params: params,
        base_model: "Qwen/Qwen2.5-7B",
        model_path: "tinker://run-123/weights/checkpoint"
      }

      assert request.base_model == "Qwen/Qwen2.5-7B"
      assert request.model_path == "tinker://run-123/weights/checkpoint"
    end

    test "encodes to JSON with required fields" do
      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{max_tokens: 100, temperature: 0.7}

      request = %SampleRequest{prompt: prompt, sampling_params: params}
      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["prompt"] == [1, 2, 3]
      assert decoded["num_samples"] == 1
      assert decoded["type"] == "sample"
      assert decoded["sampling_params"]["max_tokens"] == 100
    end

    test "encodes prompt_logprobs when true" do
      prompt = ModelInput.from_ints([1])
      params = %SamplingParams{}

      request = %SampleRequest{
        prompt: prompt,
        sampling_params: params,
        prompt_logprobs: true
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["prompt_logprobs"] == true
    end

    test "encodes prompt_logprobs when false" do
      prompt = ModelInput.from_ints([1])
      params = %SamplingParams{}

      request = %SampleRequest{
        prompt: prompt,
        sampling_params: params,
        prompt_logprobs: false
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["prompt_logprobs"] == false
    end

    test "omits prompt_logprobs when nil" do
      prompt = ModelInput.from_ints([1])
      params = %SamplingParams{}

      request = %SampleRequest{
        prompt: prompt,
        sampling_params: params,
        prompt_logprobs: nil
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded, "prompt_logprobs")
    end

    test "includes session_id and seq_id when present" do
      prompt = ModelInput.from_ints([1])
      params = %SamplingParams{}

      request = %SampleRequest{
        prompt: prompt,
        sampling_params: params,
        sampling_session_id: "sess-123",
        seq_id: 42
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["sampling_session_id"] == "sess-123"
      assert decoded["seq_id"] == 42
    end
  end

  describe "SampleResponse" do
    test "from_json/1 parses with sequences" do
      json = %{
        "sequences" => [
          %{"tokens" => [1, 2, 3], "stop_reason" => "length"}
        ],
        "type" => "sample"
      }

      response = SampleResponse.from_json(json)

      assert length(response.sequences) == 1
      assert hd(response.sequences).tokens == [1, 2, 3]
      assert response.type == "sample"
    end

    test "from_json/1 parses prompt_logprobs" do
      json = %{
        "sequences" => [%{"tokens" => [1]}],
        "prompt_logprobs" => [-0.1, -0.2, -0.3]
      }

      response = SampleResponse.from_json(json)

      assert response.prompt_logprobs == [-0.1, -0.2, -0.3]
    end

    test "from_json/1 parses topk_prompt_logprobs from tuples" do
      json = %{
        "sequences" => [%{"tokens" => [1]}],
        "topk_prompt_logprobs" => [
          [{100, -0.1}, {200, -0.5}],
          [{150, -0.2}]
        ]
      }

      response = SampleResponse.from_json(json)

      assert response.topk_prompt_logprobs == [
               [{100, -0.1}, {200, -0.5}],
               [{150, -0.2}]
             ]
    end

    test "from_json/1 parses topk_prompt_logprobs from lists" do
      json = %{
        "sequences" => [%{"tokens" => [1]}],
        "topk_prompt_logprobs" => [
          [[100, -0.1], [200, -0.5]],
          nil
        ]
      }

      response = SampleResponse.from_json(json)

      assert response.topk_prompt_logprobs == [
               [{100, -0.1}, {200, -0.5}],
               nil
             ]
    end

    test "from_json/1 parses topk_prompt_logprobs from maps" do
      json = %{
        "sequences" => [%{"tokens" => [1]}],
        "topk_prompt_logprobs" => [
          [%{"token_id" => 100, "logprob" => -0.1}]
        ]
      }

      response = SampleResponse.from_json(json)

      assert response.topk_prompt_logprobs == [[{100, -0.1}]]
    end

    test "from_json/1 handles missing optional fields" do
      json = %{"sequences" => [%{"tokens" => [1]}]}

      response = SampleResponse.from_json(json)

      assert response.prompt_logprobs == nil
      assert response.topk_prompt_logprobs == nil
      assert response.type == "sample"
    end

    test "enforces sequences" do
      assert_raise ArgumentError, fn ->
        struct!(SampleResponse, [])
      end
    end
  end

  describe "SampleStreamChunk" do
    test "from_map/1 creates token chunk" do
      map = %{
        "token" => "Hello",
        "token_id" => 12345,
        "index" => 0,
        "logprob" => -0.5
      }

      chunk = SampleStreamChunk.from_map(map)

      assert chunk.token == "Hello"
      assert chunk.token_id == 12345
      assert chunk.index == 0
      assert chunk.logprob == -0.5
      assert chunk.event_type == :token
    end

    test "from_map/1 creates done chunk from event_type" do
      map = %{"event_type" => "done", "finish_reason" => "length"}

      chunk = SampleStreamChunk.from_map(map)

      assert chunk.event_type == :done
      assert chunk.finish_reason == "length"
    end

    test "from_map/1 creates done chunk from finish_reason" do
      map = %{"finish_reason" => "stop", "total_tokens" => 100}

      chunk = SampleStreamChunk.from_map(map)

      assert chunk.event_type == :done
      assert chunk.finish_reason == "stop"
      assert chunk.total_tokens == 100
    end

    test "from_map/1 creates error chunk" do
      map = %{"event_type" => "error", "token" => "Connection lost"}

      chunk = SampleStreamChunk.from_map(map)

      assert chunk.event_type == :error
      assert chunk.token == "Connection lost"
    end

    test "from_map/1 accepts atom keys" do
      map = %{
        token: "Hi",
        token_id: 1,
        index: 0,
        event_type: :done
      }

      chunk = SampleStreamChunk.from_map(map)

      assert chunk.token == "Hi"
      assert chunk.event_type == :done
    end

    test "done/2 creates done chunk" do
      chunk = SampleStreamChunk.done("length", 50)

      assert chunk.event_type == :done
      assert chunk.finish_reason == "length"
      assert chunk.total_tokens == 50
      assert chunk.token == nil
    end

    test "done/0 creates done chunk without params" do
      chunk = SampleStreamChunk.done()

      assert chunk.event_type == :done
      assert chunk.finish_reason == nil
      assert chunk.total_tokens == nil
    end

    test "error/1 creates error chunk" do
      chunk = SampleStreamChunk.error("Timeout")

      assert chunk.event_type == :error
      assert chunk.token == "Timeout"
    end

    test "done?/1 returns true for done event_type" do
      chunk = %SampleStreamChunk{event_type: :done}
      assert SampleStreamChunk.done?(chunk)
    end

    test "done?/1 returns true when finish_reason present" do
      chunk = %SampleStreamChunk{finish_reason: "length"}
      assert SampleStreamChunk.done?(chunk)
    end

    test "done?/1 returns false for token chunk" do
      chunk = %SampleStreamChunk{token: "hello", event_type: :token}
      refute SampleStreamChunk.done?(chunk)
    end

    test "encodes to JSON" do
      chunk = %SampleStreamChunk{
        token: "Hi",
        token_id: 123,
        index: 5,
        event_type: :token
      }

      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      assert decoded["token"] == "Hi"
      assert decoded["token_id"] == 123
      assert decoded["index"] == 5
      assert decoded["event_type"] == "token"
    end
  end
end
