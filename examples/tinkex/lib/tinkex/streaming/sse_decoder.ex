defmodule Tinkex.Streaming.ServerSentEvent do
  @moduledoc """
  Representation of a server-sent event.

  SSE events contain:
  - `event` - Optional event type
  - `data` - Event payload (may be multiline)
  - `id` - Optional event ID
  - `retry` - Optional reconnection time in milliseconds
  """

  defstruct [:event, :data, :id, :retry]

  @type t :: %__MODULE__{
          event: String.t() | nil,
          data: String.t(),
          id: String.t() | nil,
          retry: non_neg_integer() | nil
        }

  @doc """
  Decode the event data as JSON if possible; otherwise return the raw string.
  """
  @spec json(t()) :: term()
  def json(%__MODULE__{data: data}) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      _ -> data
    end
  end
end

defmodule Tinkex.Streaming.SSEDecoder do
  @moduledoc """
  Minimal SSE decoder that can be fed incremental chunks.

  This decoder handles streaming SSE data by buffering incomplete
  events and emitting complete events as they are received.

  ## Example

      decoder = SSEDecoder.new()
      {events, decoder} = SSEDecoder.feed(decoder, "data: hello\\n\\n")
      # events = [%ServerSentEvent{data: "hello", ...}]

  """

  alias Tinkex.Streaming.ServerSentEvent

  defstruct buffer: ""

  @type t :: %__MODULE__{buffer: binary()}

  @doc """
  Create a new decoder.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Feed a binary chunk into the decoder, returning parsed events and updated state.
  """
  @spec feed(t(), binary()) :: {[ServerSentEvent.t()], t()}
  def feed(%__MODULE__{} = decoder, chunk) when is_binary(chunk) do
    data = decoder.buffer <> chunk
    {events, rest} = parse_events(data, [])
    {Enum.reverse(events), %__MODULE__{buffer: rest}}
  end

  @doc """
  Get remaining buffered data.
  """
  @spec buffer(t()) :: binary()
  def buffer(%__MODULE__{buffer: buf}), do: buf

  @doc """
  Check if decoder has pending buffered data.
  """
  @spec has_pending?(t()) :: boolean()
  def has_pending?(%__MODULE__{buffer: buf}), do: buf != ""

  # Parse complete events from the data buffer
  defp parse_events(data, acc) do
    case split_once(data) do
      {event_block, rest} ->
        acc =
          case decode_event(event_block) do
            nil -> acc
            event -> [event | acc]
          end

        parse_events(rest, acc)

      :incomplete ->
        {acc, data}
    end
  end

  # Split data on event boundary (double newline)
  defp split_once(data) do
    case Regex.split(~r/\r\n\r\n|\n\n|\r\r/, data, parts: 2) do
      [_single] ->
        :incomplete

      [event_block, rest] ->
        {event_block, rest}
    end
  end

  defp decode_event(""), do: nil

  defp decode_event(block) do
    lines = String.split(block, ~r/\r\n|\n|\r/)

    parsed =
      Enum.reduce(lines, %{data: [], event: nil, id: nil, retry: nil}, fn line, acc ->
        cond do
          line == "" ->
            acc

          # Comment lines start with ":"
          String.starts_with?(line, ":") ->
            acc

          true ->
            {field, value} = split_field(line)
            apply_field(acc, field, value)
        end
      end)

    %ServerSentEvent{
      event: parsed.event,
      data: Enum.join(Enum.reverse(parsed.data), "\n"),
      id: parsed.id,
      retry: parsed.retry
    }
  end

  defp split_field(line) do
    case String.split(line, ":", parts: 2) do
      [field] -> {field, ""}
      [field, value] -> {field, String.trim_leading(value)}
    end
  end

  defp apply_field(acc, "data", value), do: Map.update!(acc, :data, &[value | &1])
  defp apply_field(acc, "event", value), do: %{acc | event: value}
  defp apply_field(acc, "id", value), do: %{acc | id: value}
  defp apply_field(acc, "retry", value), do: %{acc | retry: parse_retry(value)}
  defp apply_field(acc, _unknown, _value), do: acc

  defp parse_retry(value) do
    case Integer.parse(value) do
      {retry, _} -> retry
      :error -> nil
    end
  end
end
