defmodule Tinkex.Streaming.SampleStreamTest do
  use ExUnit.Case, async: true

  alias Tinkex.Streaming.SampleStream
  alias Tinkex.Types.SampleStreamChunk
  alias Pristine.Streaming.Event

  describe "decode/1" do
    test "decodes SSE chunks to SampleStreamChunks" do
      chunks = [
        "data: {\"token\": \"Hello\", \"token_id\": 100, \"index\": 0}\n\n",
        "data: {\"token\": \" world\", \"token_id\": 101, \"index\": 1}\n\n"
      ]

      result = chunks |> SampleStream.decode() |> Enum.to_list()

      assert length(result) == 2
      assert Enum.at(result, 0).token == "Hello"
      assert Enum.at(result, 0).token_id == 100
      assert Enum.at(result, 1).token == " world"
      assert Enum.at(result, 1).token_id == 101
    end

    test "handles split chunks" do
      chunks = [
        "data: {\"token\": \"Hel",
        "lo\"}\n\n"
      ]

      result = chunks |> SampleStream.decode() |> Enum.to_list()

      assert length(result) == 1
      assert hd(result).token == "Hello"
    end

    test "handles done marker as JSON string" do
      chunks = [
        "data: {\"token\": \"Hi\"}\n\n",
        "data: \"[DONE]\"\n\n"
      ]

      result = chunks |> SampleStream.decode() |> Enum.to_list()

      assert length(result) == 2
      assert Enum.at(result, 0).token == "Hi"
      assert Enum.at(result, 1).event_type == :done
    end

    test "handles done marker as raw string" do
      chunks = [
        "data: {\"token\": \"Hi\"}\n\n",
        "data: [DONE]\n\n"
      ]

      result = chunks |> SampleStream.decode() |> Enum.to_list()

      assert length(result) == 2
      assert Enum.at(result, 0).token == "Hi"
      assert Enum.at(result, 1).event_type == :done
    end

    test "handles finish_reason in data" do
      chunks = [
        "data: {\"token\": \"end\", \"finish_reason\": \"length\"}\n\n"
      ]

      result = chunks |> SampleStream.decode() |> Enum.to_list()

      assert length(result) == 1
      chunk = hd(result)
      assert chunk.token == "end"
      assert chunk.finish_reason == "length"
      assert chunk.event_type == :done
    end

    test "ignores empty data events" do
      chunks = [
        "data: {\"token\": \"Hi\"}\n\n",
        "data: \n\n",
        "data: {\"token\": \"!\", \"finish_reason\": \"stop\"}\n\n"
      ]

      result = chunks |> SampleStream.decode() |> Enum.to_list()

      assert length(result) == 2
    end

    test "ignores comment lines" do
      chunks = [
        ": this is a comment\n",
        "data: {\"token\": \"Hi\"}\n\n"
      ]

      result = chunks |> SampleStream.decode() |> Enum.to_list()

      assert length(result) == 1
      assert hd(result).token == "Hi"
    end

    test "handles multiple events per chunk" do
      chunks = [
        "data: {\"token\": \"A\"}\n\ndata: {\"token\": \"B\"}\n\n"
      ]

      result = chunks |> SampleStream.decode() |> Enum.to_list()

      assert length(result) == 2
      assert Enum.at(result, 0).token == "A"
      assert Enum.at(result, 1).token == "B"
    end
  end

  describe "event_to_chunk/1" do
    test "converts event with token data" do
      event = %Event{data: ~s({"token": "Hello", "token_id": 123, "index": 0})}

      chunk = SampleStream.event_to_chunk(event)

      assert chunk.token == "Hello"
      assert chunk.token_id == 123
      assert chunk.index == 0
      assert chunk.event_type == :token
    end

    test "converts event with finish_reason" do
      event = %Event{data: ~s({"finish_reason": "length", "total_tokens": 50})}

      chunk = SampleStream.event_to_chunk(event)

      assert chunk.finish_reason == "length"
      assert chunk.total_tokens == 50
      assert chunk.event_type == :done
    end

    test "converts done event from SSE event type" do
      event = %Event{event: "done", data: ~s({"total_tokens": 100})}

      chunk = SampleStream.event_to_chunk(event)

      assert chunk.event_type == :done
      assert chunk.total_tokens == 100
    end

    test "converts error event from SSE event type" do
      event = %Event{event: "error", data: ~s({"token": "Connection lost"})}

      chunk = SampleStream.event_to_chunk(event)

      assert chunk.event_type == :error
      assert chunk.token == "Connection lost"
    end

    test "returns nil for nil data" do
      event = %Event{data: nil}

      assert SampleStream.event_to_chunk(event) == nil
    end

    test "returns nil for empty data" do
      event = %Event{data: ""}

      assert SampleStream.event_to_chunk(event) == nil
    end

    test "returns done chunk for [DONE] marker" do
      event = %Event{data: "[DONE]"}

      chunk = SampleStream.event_to_chunk(event)

      assert chunk.event_type == :done
    end

    test "handles logprob field" do
      event = %Event{data: ~s({"token": "x", "logprob": -0.5})}

      chunk = SampleStream.event_to_chunk(event)

      assert chunk.token == "x"
      assert chunk.logprob == -0.5
    end
  end

  describe "collect_text/1" do
    test "collects all tokens into text" do
      chunks = [
        %SampleStreamChunk{token: "Hello", event_type: :token},
        %SampleStreamChunk{token: " ", event_type: :token},
        %SampleStreamChunk{token: "world", event_type: :token},
        %SampleStreamChunk{finish_reason: "stop", event_type: :done}
      ]

      {:ok, text, final} = SampleStream.collect_text(chunks)

      assert text == "Hello world"
      assert final.finish_reason == "stop"
    end

    test "stops on error chunk" do
      chunks = [
        %SampleStreamChunk{token: "Hello", event_type: :token},
        %SampleStreamChunk{token: "Connection lost", event_type: :error},
        %SampleStreamChunk{token: " world", event_type: :token}
      ]

      {:error, error_chunk} = SampleStream.collect_text(chunks)

      assert error_chunk.event_type == :error
      assert error_chunk.token == "Connection lost"
    end

    test "handles nil tokens" do
      chunks = [
        %SampleStreamChunk{token: "Hi", event_type: :token},
        %SampleStreamChunk{token: nil, event_type: :token},
        %SampleStreamChunk{token: "!", event_type: :token},
        %SampleStreamChunk{event_type: :done}
      ]

      {:ok, text, _final} = SampleStream.collect_text(chunks)

      assert text == "Hi!"
    end

    test "handles empty stream" do
      chunks = []

      {:ok, text, final} = SampleStream.collect_text(chunks)

      assert text == ""
      assert final == nil
    end

    test "handles stream with only done" do
      chunks = [
        %SampleStreamChunk{finish_reason: "length", event_type: :done}
      ]

      {:ok, text, final} = SampleStream.collect_text(chunks)

      assert text == ""
      assert final.finish_reason == "length"
    end
  end

  describe "decode/2 with options" do
    test "calls on_error for parse failures" do
      errors = []
      on_error = fn e -> send(self(), {:error, e}) end

      chunks = [
        "data: {\"token\": \"Hi\"}\n\n",
        "data: not valid json\n\n",
        "data: {\"token\": \"!\"}\n\n"
      ]

      result = chunks |> SampleStream.decode(on_error: on_error) |> Enum.to_list()

      # Should still get the valid chunks
      assert length(result) == 2
      assert Enum.at(result, 0).token == "Hi"
      assert Enum.at(result, 1).token == "!"
    end
  end
end
