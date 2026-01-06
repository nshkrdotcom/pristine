defmodule Tinkex.Types.SamplingTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{StopReason, SamplingParams, SampledSequence}

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
end
