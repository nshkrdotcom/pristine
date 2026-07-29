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

  alias Pristine.Core.{Context, HTTPMethod, Request, StreamResponse}
  alias Pristine.Streaming.{Event, SSEDecoder}

  @default_timeout 60_000

  @impl true
  def stream(%Request{} = request, %Context{} = context) do
    finch_name = get_pool_name(request, context)
    timeout = get_timeout(request, context)

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

  defp get_pool_name(%Request{metadata: metadata}, %Context{transport_opts: opts}) do
    metadata
    |> Map.get(:pool_name)
    |> fallback_pool(Keyword.get(opts, :pool_name))
    |> fallback_pool(get_finch_name(%Context{transport_opts: opts}))
  end

  defp get_timeout(%Request{metadata: metadata}, %Context{transport_opts: opts}) do
    case Map.get(metadata, :timeout) do
      timeout when is_integer(timeout) and timeout >= 0 ->
        timeout

      _ ->
        Keyword.get(opts, :receive_timeout, Keyword.get(opts, :timeout, @default_timeout))
    end
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
    HTTPMethod.telemetry(method)
  end

  defp fallback_pool(nil, fallback), do: fallback
  defp fallback_pool(pool, _fallback), do: pool

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

    owner = self()
    ref = make_ref()
    {:ok, last_event_id_ref} = Agent.start_link(fn -> nil end)
    cancelled_ref = :atomics.new(1, [])

    {:ok, producer} =
      Task.start(fn ->
        run_stream(finch_request, finch_name, timeout, owner, ref, last_event_id_ref)
      end)

    producer_monitor = Process.monitor(producer)

    # Wait for initial metadata (status + headers)
    receive do
      {^ref, :metadata, status, headers} ->
        Process.demonitor(producer_monitor, [:flush])

        # Create the event stream that consumes from the task
        event_stream = create_event_stream(ref, producer, last_event_id_ref, cancelled_ref)
        cancel_fun = fn -> cancel_stream(producer, last_event_id_ref, cancelled_ref) end
        {:ok, status, headers, event_stream, last_event_id_ref, cancel_fun}

      {^ref, :error, reason} ->
        Process.demonitor(producer_monitor, [:flush])
        stop_producer(producer)
        stop_last_event_id(last_event_id_ref)
        {:error, reason}

      {:DOWN, ^producer_monitor, :process, ^producer, reason} ->
        stop_last_event_id(last_event_id_ref)
        {:error, {:stream_start_failed, reason}}
    after
      timeout ->
        Process.demonitor(producer_monitor, [:flush])
        stop_producer(producer)
        stop_last_event_id(last_event_id_ref)
        {:error, :timeout}
    end
  end

  defp run_stream(finch_request, finch_name, timeout, owner, ref, last_event_id_ref) do
    Finch.stream(
      finch_request,
      finch_name,
      {nil, nil, SSEDecoder.new(), false},
      fn
        {:status, status}, {_, headers, decoder, metadata_sent?} ->
          {status, headers, decoder, metadata_sent?}

        {:headers, headers}, {status, _, decoder, _metadata_sent?} ->
          header_map = Map.new(headers)
          send(owner, {ref, :metadata, status, header_map})
          {status, header_map, decoder, true}

        {:data, chunk}, {status, headers, decoder, metadata_sent?} ->
          handle_data_chunk(
            chunk,
            status,
            headers,
            decoder,
            metadata_sent?,
            ref,
            last_event_id_ref
          )
      end,
      receive_timeout: timeout
    )
    |> case do
      {:ok, {_status, _headers, _decoder, true}} ->
        send_terminal_on_demand(ref, :done, timeout)

      {:ok, _acc} ->
        send(owner, {ref, :error, :missing_response_metadata})

      {:error, exception, {_status, _headers, _decoder, true}} ->
        case send_terminal_on_demand(ref, {:error, exception}, timeout) do
          :sent -> :ok
          :expired -> exit(:stream_failed)
        end

      {:error, exception, _partial_response} ->
        send(owner, {ref, :error, exception})
        {:error, exception}
    end
  end

  defp create_event_stream(ref, producer, last_event_id_ref, cancelled_ref) do
    Stream.resource(
      fn -> {ref, producer, Process.monitor(producer), :idle} end,
      fn
        {_ref, _producer, _monitor, :done} = state ->
          {:halt, state}

        {r, p, monitor, :idle} ->
          send(p, {r, :demand, self()})
          await_stream_message(r, p, monitor, cancelled_ref)

        {r, p, monitor, :waiting} ->
          await_stream_message(r, p, monitor, cancelled_ref)
      end,
      fn {_ref, producer, monitor, _status} ->
        Process.demonitor(monitor, [:flush])
        cancel_stream(producer, last_event_id_ref, cancelled_ref)
      end
    )
    |> Stream.reject(&is_nil/1)
  end

  defp await_stream_message(ref, producer, monitor, cancelled_ref) do
    receive do
      {^ref, :event, event} ->
        {[event], {ref, producer, monitor, :idle}}

      {^ref, :done} ->
        {:halt, {ref, producer, monitor, :done}}

      {^ref, :error, _reason} ->
        raise RuntimeError, "Finch stream failed after response metadata"

      {:DOWN, ^monitor, :process, ^producer, :normal} ->
        {:halt, {ref, producer, monitor, :done}}

      {:DOWN, ^monitor, :process, ^producer, _reason} ->
        if cancelled?(cancelled_ref) do
          {:halt, {ref, producer, monitor, :done}}
        else
          raise RuntimeError, "Finch stream producer terminated unexpectedly"
        end
    after
      100 ->
        {[], {ref, producer, monitor, :waiting}}
    end
  end

  defp handle_data_chunk(
         chunk,
         status,
         headers,
         decoder,
         metadata_sent?,
         ref,
         last_event_id_ref
       ) do
    {new_events, new_decoder} = SSEDecoder.feed(decoder, chunk)
    update_last_event_id(last_event_id_ref, decoder, new_decoder)
    send_events(ref, new_events)
    {status, headers, new_decoder, metadata_sent?}
  end

  defp update_last_event_id(last_event_id_ref, decoder, new_decoder) do
    last_event_id = SSEDecoder.last_event_id(new_decoder)

    if last_event_id != nil and last_event_id != decoder.last_event_id do
      Agent.update(last_event_id_ref, fn _ -> last_event_id end)
    end
  end

  defp send_events(ref, events) do
    Enum.each(events, fn event ->
      receive do
        {^ref, :demand, consumer} when is_pid(consumer) ->
          send(consumer, {ref, :event, event})
      end
    end)
  end

  defp send_terminal_on_demand(ref, terminal, timeout) do
    receive do
      {^ref, :demand, consumer} when is_pid(consumer) ->
        send_terminal(consumer, ref, terminal)
        :sent
    after
      timeout -> :expired
    end
  end

  defp send_terminal(consumer, ref, :done), do: send(consumer, {ref, :done})

  defp send_terminal(consumer, ref, {:error, reason}),
    do: send(consumer, {ref, :error, reason})

  defp cancel_stream(producer, last_event_id_ref, cancelled_ref) do
    :atomics.put(cancelled_ref, 1, 1)
    stop_producer(producer)
    stop_last_event_id(last_event_id_ref)
    :ok
  end

  defp cancelled?(cancelled_ref), do: :atomics.get(cancelled_ref, 1) == 1

  defp stop_producer(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
  end

  defp stop_last_event_id(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      stop_agent(pid)
    else
      :ok
    end
  end

  defp stop_agent(pid) do
    Agent.stop(pid)
  catch
    :exit, _reason -> :ok
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
