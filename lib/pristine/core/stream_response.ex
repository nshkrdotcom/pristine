defmodule Pristine.Core.StreamResponse do
  @moduledoc """
  Response wrapper for streaming HTTP responses.

  Contains an enumerable stream of events instead of a complete body.
  This is used for SSE (Server-Sent Events) and other streaming responses.

  ## Fields

    * `:stream` - An enumerable that yields events (required)
    * `:status` - HTTP status code (required)
    * `:headers` - Response headers as a map (required)
    * `:metadata` - Additional metadata (optional, defaults to empty map)

  ## Example

      %StreamResponse{
        stream: events,
        status: 200,
        headers: %{"content-type" => "text/event-stream"},
        metadata: %{request_id: "req_123"}
      }

  ## Usage

  The stream can be consumed lazily:

      {:ok, response} = StreamTransport.stream(request, context)

      response.stream
      |> Stream.each(fn event ->
        IO.puts("Got event: \#{inspect(event)}")
      end)
      |> Stream.run()

  Or collected into a list:

      events = Enum.to_list(response.stream)
  """

  @type t :: %__MODULE__{
          stream: Enumerable.t(),
          status: integer(),
          headers: map(),
          metadata: map()
        }

  @enforce_keys [:stream, :status, :headers]
  defstruct [:stream, :status, :headers, metadata: %{}]

  alias Pristine.Streaming.Event

  @doc """
  Dispatch a single event to a handler module based on its type.
  """
  @spec dispatch_event(Event.t(), module()) :: {:ok, term()} | {:error, term()} | term()
  def dispatch_event(%Event{} = event, handler_module) do
    payload = Event.json!(event)

    case event.event do
      "message_start" -> handler_module.on_message_start(payload)
      "content_block_start" -> handler_module.on_content_block_start(payload)
      "content_block_delta" -> handler_module.on_content_block_delta(payload)
      "content_block_stop" -> handler_module.on_content_block_stop(payload)
      "message_stop" -> handler_module.on_message_stop(payload)
      "error" -> handler_module.on_error(payload)
      _ -> handler_module.on_unknown(event.event, event.data)
    end
  end

  @doc """
  Map a stream of events through a handler module.
  """
  @spec dispatch_stream(t(), module()) :: Enumerable.t()
  def dispatch_stream(%__MODULE__{stream: stream}, handler_module) do
    Stream.map(stream, &dispatch_event(&1, handler_module))
  end

  @doc """
  Cancel the underlying stream when supported by the transport.
  """
  @spec cancel(t()) :: :ok
  def cancel(%__MODULE__{metadata: %{cancel: cancel_fun}}) when is_function(cancel_fun, 0) do
    cancel_fun.()
    :ok
  end

  def cancel(_response), do: :ok

  @doc """
  Return the latest Last-Event-ID value when available.
  """
  @spec last_event_id(t()) :: String.t() | nil
  def last_event_id(%__MODULE__{metadata: %{last_event_id_ref: ref}}) do
    cond do
      is_pid(ref) ->
        Agent.get(ref, & &1)

      is_function(ref, 0) ->
        ref.()

      true ->
        nil
    end
  end

  def last_event_id(_response), do: nil
end
