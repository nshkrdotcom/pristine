defmodule Pristine.Ports.StreamTransport do
  @moduledoc """
  Port for streaming HTTP transport.

  Unlike the regular Transport port which returns complete responses,
  this port returns StreamResponse with an enumerable body for handling
  SSE (Server-Sent Events) and other streaming responses.

  ## Implementation Requirements

  Adapters implementing this behaviour should:

  1. Make an HTTP request with appropriate streaming headers
  2. Return a StreamResponse with an enumerable that yields events
  3. Handle connection lifecycle (cleanup on enumeration completion)
  4. Parse SSE events if content-type is `text/event-stream`

  ## Example Adapter

      defmodule MyStreamAdapter do
        @behaviour Pristine.Ports.StreamTransport

        @impl true
        def stream(%Request{} = request, %Context{} = context) do
          # Make streaming HTTP request
          # Parse SSE events
          # Return StreamResponse
          {:ok, %StreamResponse{stream: events, status: 200, headers: headers}}
        end
      end
  """

  alias Pristine.Core.{Context, Request, StreamResponse}

  @doc """
  Make a streaming HTTP request and return an enumerable of events.

  ## Parameters

    * `request` - The request to send
    * `context` - Runtime context with configuration

  ## Returns

    * `{:ok, StreamResponse.t()}` - Success with streaming response
    * `{:error, term()}` - Error during connection or initial response

  ## Notes

  The returned stream is lazy - it will only fetch data as it is consumed.
  Callers should ensure they consume or close the stream to release
  resources.
  """
  @callback stream(Request.t(), Context.t()) ::
              {:ok, StreamResponse.t()} | {:error, term()}
end
