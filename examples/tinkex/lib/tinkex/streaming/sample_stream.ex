defmodule Tinkex.Streaming.SampleStream do
  @moduledoc """
  Stream processing for sampling responses.

  Converts SSE events from the Tinker streaming API into `SampleStreamChunk` structs.
  Uses Pristine's SSE decoder for the underlying parsing.

  ## Usage

      # Convert SSE chunks to SampleStreamChunks
      stream
      |> SampleStream.decode()
      |> Enum.each(fn chunk ->
        IO.write(chunk.token)
      end)

      # Process until done
      stream
      |> SampleStream.decode()
      |> Enum.take_while(fn chunk -> not SampleStreamChunk.done?(chunk) end)
      |> Enum.map(& &1.token)
      |> Enum.join()
  """

  alias Pristine.Streaming.{SSEDecoder, Event}
  alias Tinkex.Types.SampleStreamChunk

  @doc """
  Decode a stream of binary chunks into SampleStreamChunk structs.

  Uses Pristine's SSEDecoder to parse SSE events, then converts each
  event's JSON data into a SampleStreamChunk.

  ## Parameters

  - `chunks` - Enumerable of binary chunks from HTTP response body

  ## Returns

  Stream of `SampleStreamChunk.t()` structs

  ## Examples

      # From HTTP stream
      {:ok, stream} = http_client.post_stream(config, "/v1/sample_stream", body)

      stream
      |> SampleStream.decode()
      |> Enum.each(fn chunk ->
        case chunk.event_type do
          :token -> IO.write(chunk.token)
          :done -> IO.puts("\\nDone!")
          :error -> IO.puts("Error: \#{chunk.token}")
        end
      end)
  """
  @spec decode(Enumerable.t()) :: Enumerable.t()
  def decode(chunks) do
    chunks
    |> SSEDecoder.decode_stream()
    |> Stream.map(&event_to_chunk/1)
    |> Stream.reject(&is_nil/1)
  end

  @doc """
  Decode a stream with options.

  ## Options

  - `:on_error` - Function to call on parse errors (default: ignore)
  - `:last_event_id` - Last event ID for reconnection

  ## Examples

      stream
      |> SampleStream.decode(on_error: fn e -> Logger.warning("SSE error: \#{inspect(e)}") end)
      |> Enum.to_list()
  """
  @spec decode(Enumerable.t(), keyword()) :: Enumerable.t()
  def decode(chunks, opts) do
    _on_error = Keyword.get(opts, :on_error, fn _ -> :ok end)
    sse_opts = Keyword.take(opts, [:last_event_id])

    chunks
    |> SSEDecoder.decode_stream(sse_opts)
    |> Stream.map(&event_to_chunk/1)
    |> Stream.reject(&is_nil/1)
  end

  @doc """
  Convert a single SSE event to a SampleStreamChunk.

  Returns `nil` if the event cannot be converted (e.g., ping events).

  ## Examples

      event = %Pristine.Streaming.Event{data: ~s({"token": "Hello", "token_id": 123})}
      chunk = SampleStream.event_to_chunk(event)
      chunk.token
      #=> "Hello"
  """
  @spec event_to_chunk(Event.t()) :: SampleStreamChunk.t() | nil
  def event_to_chunk(%Event{data: nil}), do: nil
  def event_to_chunk(%Event{data: ""}), do: nil

  def event_to_chunk(%Event{event: event_type, data: data}) do
    case Jason.decode(data) do
      {:ok, map} when is_map(map) ->
        # Handle special event types from SSE
        map = maybe_add_event_type(map, event_type)
        SampleStreamChunk.from_map(map)

      {:ok, "[DONE]"} ->
        SampleStreamChunk.done()

      {:ok, _} ->
        nil

      {:error, _} ->
        # Check for [DONE] as raw string
        if String.trim(data) == "[DONE]" do
          SampleStreamChunk.done()
        else
          nil
        end
    end
  end

  # Add event_type from SSE event type field if present
  defp maybe_add_event_type(map, nil), do: map
  defp maybe_add_event_type(map, "message"), do: map
  defp maybe_add_event_type(map, "token"), do: Map.put_new(map, "event_type", "token")
  defp maybe_add_event_type(map, "done"), do: Map.put_new(map, "event_type", "done")
  defp maybe_add_event_type(map, "error"), do: Map.put_new(map, "event_type", "error")
  defp maybe_add_event_type(map, _other), do: map

  @doc """
  Collect all tokens from a stream into a single string.

  Stops when a done or error chunk is received.

  ## Parameters

  - `stream` - Stream of SampleStreamChunk structs

  ## Returns

  `{:ok, text, final_chunk}` on successful completion, or
  `{:error, error_chunk}` if an error occurred.

  ## Examples

      {:ok, text, final} = stream |> SampleStream.decode() |> SampleStream.collect_text()
      IO.puts(text)
  """
  @spec collect_text(Enumerable.t()) ::
          {:ok, String.t(), SampleStreamChunk.t()} | {:error, SampleStreamChunk.t()}
  def collect_text(chunks) do
    chunks
    |> Enum.reduce_while({[], nil}, fn chunk, {tokens, _last} ->
      case chunk.event_type do
        :error ->
          {:halt, {:error, chunk}}

        :done ->
          {:halt, {:ok, tokens, chunk}}

        :token ->
          if chunk.token do
            {:cont, {[chunk.token | tokens], chunk}}
          else
            {:cont, {tokens, chunk}}
          end
      end
    end)
    |> case do
      {:error, chunk} -> {:error, chunk}
      {:ok, tokens, chunk} -> {:ok, tokens |> Enum.reverse() |> Enum.join(), chunk}
      {tokens, nil} -> {:ok, tokens |> Enum.reverse() |> Enum.join(), nil}
      {tokens, chunk} -> {:ok, tokens |> Enum.reverse() |> Enum.join(), chunk}
    end
  end
end
