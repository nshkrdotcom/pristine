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
end
