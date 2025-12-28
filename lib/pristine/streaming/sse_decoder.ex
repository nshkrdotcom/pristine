defmodule Pristine.Streaming.SSEDecoder do
  @moduledoc """
  Stateful decoder for Server-Sent Events (SSE) streams.

  Implements the SSE specification: https://html.spec.whatwg.org/multipage/server-sent-events.html

  ## Basic Usage

      decoder = SSEDecoder.new()
      {events, decoder} = SSEDecoder.feed(decoder, chunk)

  ## Streaming Usage

      chunks
      |> SSEDecoder.decode_stream()
      |> Enum.each(&process_event/1)

  ## SSE Format

  The decoder handles the standard SSE format:

      event: eventType
      id: eventId
      retry: 5000
      data: line1
      data: line2

  Events are terminated by a blank line (`\\n\\n`, `\\r\\n\\r\\n`, or `\\r\\r`).
  Lines starting with `:` are comments and are ignored.
  """

  alias Pristine.Streaming.Event

  @type t :: %__MODULE__{
          buffer: binary()
        }

  defstruct buffer: ""

  @doc """
  Create a new decoder with an empty buffer.

  ## Example

      decoder = SSEDecoder.new()
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Feed a chunk of data to the decoder.

  Returns `{events, new_decoder}` where `events` is a list of complete
  events parsed from the accumulated data.

  ## Examples

      iex> decoder = Pristine.Streaming.SSEDecoder.new()
      iex> {events, _decoder} = Pristine.Streaming.SSEDecoder.feed(decoder, "data: hello\\n\\n")
      iex> length(events)
      1

      iex> decoder = Pristine.Streaming.SSEDecoder.new()
      iex> {events1, decoder} = Pristine.Streaming.SSEDecoder.feed(decoder, "data: hel")
      iex> {events2, _decoder} = Pristine.Streaming.SSEDecoder.feed(decoder, "lo\\n\\n")
      iex> {length(events1), length(events2)}
      {0, 1}
  """
  @spec feed(t(), binary()) :: {[Event.t()], t()}
  def feed(%__MODULE__{buffer: buffer} = _decoder, chunk) when is_binary(chunk) do
    data = buffer <> chunk
    {events, rest} = parse_events(data, [])
    {Enum.reverse(events), %__MODULE__{buffer: rest}}
  end

  @doc """
  Create a stream of events from an enumerable of chunks.

  This is useful for processing SSE responses from HTTP clients that
  provide chunked data as an enumerable or stream.

  ## Examples

      chunks
      |> SSEDecoder.decode_stream()
      |> Enum.each(fn event ->
        IO.puts("Got event: \#{event.data}")
      end)

      # With JSON parsing
      chunks
      |> SSEDecoder.decode_stream()
      |> Stream.map(&Event.json!/1)
      |> Enum.to_list()
  """
  @spec decode_stream(Enumerable.t()) :: Enumerable.t()
  def decode_stream(chunks) do
    Stream.transform(chunks, new(), fn chunk, decoder ->
      {events, new_decoder} = feed(decoder, chunk)
      {events, new_decoder}
    end)
  end

  # Parse complete events from the buffer
  defp parse_events(data, acc) do
    case split_event_block(data) do
      :incomplete ->
        {acc, data}

      {event_block, rest} ->
        event = decode_event(event_block)
        parse_events(rest, [event | acc])
    end
  end

  # Split on event boundary (blank line)
  defp split_event_block(data) do
    case Regex.split(~r/\r\n\r\n|\n\n|\r\r/, data, parts: 2) do
      [_single] ->
        :incomplete

      [event_block, rest] ->
        {event_block, rest}
    end
  end

  # Decode a single event block into an Event struct
  defp decode_event(block) do
    lines = String.split(block, ~r/\r\n|\n|\r/)

    parsed =
      Enum.reduce(lines, %{data: [], event: nil, id: nil, retry: nil}, fn line, acc ->
        cond do
          line == "" ->
            acc

          String.starts_with?(line, ":") ->
            # Comment line - ignore
            acc

          true ->
            {field, value} = parse_field(line)
            apply_field(acc, field, value)
        end
      end)

    %Event{
      event: parsed.event,
      data: Enum.join(Enum.reverse(parsed.data), "\n"),
      id: parsed.id,
      retry: parsed.retry
    }
  end

  # Parse a field:value line
  defp parse_field(line) do
    case String.split(line, ":", parts: 2) do
      [field] -> {field, ""}
      [field, value] -> {field, String.trim_leading(value)}
    end
  end

  # Apply a parsed field to the accumulator
  defp apply_field(acc, "data", value), do: Map.update!(acc, :data, &[value | &1])
  defp apply_field(acc, "event", value), do: %{acc | event: value}
  defp apply_field(acc, "id", value), do: %{acc | id: value}
  defp apply_field(acc, "retry", value), do: %{acc | retry: parse_retry(value)}
  defp apply_field(acc, _unknown_field, _value), do: acc

  # Parse retry as integer, ignoring invalid values
  defp parse_retry(value) do
    case Integer.parse(value) do
      {retry, _} -> retry
      :error -> nil
    end
  end
end
