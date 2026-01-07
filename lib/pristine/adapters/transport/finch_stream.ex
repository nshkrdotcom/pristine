defmodule Pristine.Adapters.Transport.FinchStream do
  @moduledoc """
  Streaming HTTP transport adapter using Finch.

  Uses Finch.stream/5 to handle chunked responses and SSE streams.
  Returns a StreamResponse with an enumerable that yields parsed SSE events.

  ## Configuration

  Configure via context transport_opts:

      context = %Context{
        transport_opts: [
          finch: MyApp.Finch,          # Finch instance name
          receive_timeout: 60_000       # Timeout for receiving data (ms)
        ]
      }

  ## Usage

      {:ok, response} = FinchStream.stream(request, context)

      response.stream
      |> Enum.each(fn event ->
        IO.puts("Event: \#{event.data}")
      end)
  """

  @behaviour Pristine.Ports.StreamTransport

  alias Pristine.Core.{Context, Request, StreamResponse}
  alias Pristine.Streaming.{Event, SSEDecoder}

  @default_timeout 60_000

  @impl true
  def stream(%Request{} = request, %Context{} = context) do
    finch_name = Map.get(request.metadata, :pool_name, get_finch_name(context))
    timeout = get_timeout(context)

    finch_request = build_finch_request(request)

    # Use a stream that consumes the Finch response and yields SSE events
    case start_streaming(finch_request, finch_name, timeout) do
      {:ok, status, headers, event_stream, last_event_id_ref, cancel_fun} ->
        {:ok,
         %StreamResponse{
           stream: event_stream,
           status: status,
           headers: headers,
           metadata: %{
             url: request.url,
             method: request.method,
             last_event_id_ref: last_event_id_ref,
             cancel: cancel_fun
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_finch_name(%Context{transport_opts: opts}) do
    Keyword.get(opts, :finch, Pristine.Finch)
  end

  defp get_timeout(%Context{transport_opts: opts}) do
    Keyword.get(opts, :receive_timeout, @default_timeout)
  end

  defp build_finch_request(%Request{method: method, url: url, headers: headers, body: body}) do
    header_list =
      headers
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    normalized_method = normalize_method(method)
    Finch.build(normalized_method, url, header_list, body)
  end

  defp normalize_method(method) when is_atom(method), do: method

  defp normalize_method(method) when is_binary(method) do
    method
    |> String.downcase()
    |> String.to_existing_atom()
  end

  # Start streaming and return status, headers, and an event stream
  defp start_streaming(finch_request, finch_name, timeout) do
    # We use Stream.resource to create a lazy enumerable that:
    # 1. Starts the Finch stream request
    # 2. Accumulates chunks and yields parsed SSE events
    # 3. Cleans up on completion

    # First, we need to get status and headers before we can return
    # We'll use a synchronous initial request to get metadata, then stream body

    # For true streaming, we use Finch.stream with an accumulator
    # But we need status/headers upfront for the StreamResponse

    # Strategy: Use a Task to run the streaming request, and a Stream.resource
    # that pulls from it via a mailbox pattern

    parent = self()
    ref = make_ref()
    {:ok, last_event_id_ref} = Agent.start_link(fn -> nil end)

    task =
      Task.async(fn ->
        run_stream(finch_request, finch_name, timeout, parent, ref, last_event_id_ref)
      end)

    # Wait for initial metadata (status + headers)
    receive do
      {^ref, :metadata, status, headers} ->
        # Create the event stream that consumes from the task
        event_stream = create_event_stream(ref, task, last_event_id_ref)
        cancel_fun = fn -> cancel_stream(task, ref, parent, last_event_id_ref) end
        {:ok, status, headers, event_stream, last_event_id_ref, cancel_fun}

      {^ref, :error, reason} ->
        Task.shutdown(task, :brutal_kill)
        stop_last_event_id(last_event_id_ref)
        {:error, reason}
    after
      timeout ->
        Task.shutdown(task, :brutal_kill)
        stop_last_event_id(last_event_id_ref)
        {:error, :timeout}
    end
  end

  defp run_stream(finch_request, finch_name, timeout, parent, ref, last_event_id_ref) do
    Finch.stream(
      finch_request,
      finch_name,
      {nil, nil, SSEDecoder.new(), []},
      fn
        {:status, status}, {_, headers, decoder, events} ->
          {status, headers, decoder, events}

        {:headers, headers}, {status, _, decoder, events} ->
          header_map = Map.new(headers)
          send(parent, {ref, :metadata, status, header_map})
          {status, header_map, decoder, events}

        {:data, chunk}, {status, headers, decoder, events} ->
          handle_data_chunk(
            chunk,
            status,
            headers,
            decoder,
            events,
            parent,
            ref,
            last_event_id_ref
          )
      end,
      receive_timeout: timeout
    )
    |> case do
      {:ok, _acc} ->
        send(parent, {ref, :done})
        :ok

      {:error, exception, _partial_response} ->
        send(parent, {ref, :error, exception})
        {:error, exception}
    end
  end

  defp create_event_stream(ref, task, last_event_id_ref) do
    Stream.resource(
      fn -> {ref, task, :running} end,
      fn
        {_ref, _task, :done} = state ->
          {:halt, state}

        {r, t, :running} = state ->
          receive do
            {^r, :event, event} ->
              {[event], state}

            {^r, :done} ->
              {:halt, {r, t, :done}}

            {^r, :error, _reason} ->
              {:halt, {r, t, :done}}
          after
            # Yield control periodically
            100 ->
              {[], state}
          end
      end,
      fn {_ref, task, _status} ->
        # Cleanup: ensure task is completed
        case Task.yield(task, 0) do
          nil -> Task.shutdown(task, :brutal_kill)
          _ -> :ok
        end

        stop_last_event_id(last_event_id_ref)
      end
    )
    |> Stream.reject(&is_nil/1)
  end

  defp handle_data_chunk(chunk, status, headers, decoder, events, parent, ref, last_event_id_ref) do
    {new_events, new_decoder} = SSEDecoder.feed(decoder, chunk)
    update_last_event_id(last_event_id_ref, decoder, new_decoder)
    send_events(parent, ref, new_events)
    {status, headers, new_decoder, events ++ new_events}
  end

  defp update_last_event_id(last_event_id_ref, decoder, new_decoder) do
    last_event_id = SSEDecoder.last_event_id(new_decoder)

    if last_event_id != nil and last_event_id != decoder.last_event_id do
      Agent.update(last_event_id_ref, fn _ -> last_event_id end)
    end
  end

  defp send_events(parent, ref, events) do
    Enum.each(events, fn event ->
      send(parent, {ref, :event, event})
    end)
  end

  defp cancel_stream(task, ref, parent, last_event_id_ref) do
    Task.shutdown(task, :brutal_kill)
    send(parent, {ref, :done})
    stop_last_event_id(last_event_id_ref)
    :ok
  end

  defp stop_last_event_id(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      Agent.stop(pid)
    else
      :ok
    end
  end

  @doc """
  Decode a raw binary SSE body into a list of events.

  This is useful when you have a complete SSE response body and want
  to parse it into events.

  ## Example

      events = FinchStream.decode_sse_body(body)
  """
  @spec decode_sse_body(binary()) :: [Event.t()]
  def decode_sse_body(body) when is_binary(body) do
    # Ensure body ends with event terminator if it doesn't already
    normalized_body =
      if String.ends_with?(body, "\n\n") or String.ends_with?(body, "\r\r") or
           String.ends_with?(body, "\r\n\r\n") do
        body
      else
        body <> "\n\n"
      end

    {events, _decoder} = SSEDecoder.feed(SSEDecoder.new(), normalized_body)

    # Filter out empty events that may result from trailing terminators
    Enum.reject(events, fn event ->
      is_nil(event.event) and event.data == "" and is_nil(event.id) and is_nil(event.retry)
    end)
  end
end
