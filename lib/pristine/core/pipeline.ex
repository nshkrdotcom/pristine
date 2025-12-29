defmodule Pristine.Core.Pipeline do
  @moduledoc """
  Execute manifest-defined endpoints through the request pipeline.

  Provides both synchronous (`execute/5`) and streaming (`execute_stream/5`)
  execution modes for manifest-defined API endpoints.
  """

  alias Pristine.Core.{Context, Headers, Request, Response, StreamResponse, TelemetryHeaders, Url}
  alias Pristine.Manifest

  @spec execute(Manifest.t(), String.t() | atom(), term(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute(%Manifest{} = manifest, endpoint_id, payload, %Context{} = context, opts \\ []) do
    endpoint = Manifest.fetch_endpoint!(manifest, endpoint_id)

    serializer = context.serializer || raise ArgumentError, "serializer is required"
    transport = context.transport || raise ArgumentError, "transport is required"
    retry = context.retry || Pristine.Adapters.Retry.Noop
    rate_limiter = context.rate_limiter || Pristine.Adapters.RateLimit.Noop
    circuit_breaker = context.circuit_breaker || Pristine.Adapters.CircuitBreaker.Foundation
    telemetry = context.telemetry || Pristine.Adapters.Telemetry.Noop

    request_schema = Map.get(context.type_schemas, endpoint.request)
    response_schema = Map.get(context.type_schemas, endpoint.response)

    telemetry.emit(:request_start, %{endpoint_id: endpoint.id}, %{})
    start_time = System.monotonic_time(:millisecond)

    retry_key = {:pristine_retry_attempt, make_ref()}
    Process.put(retry_key, 0)

    before_attempt = fn attempt ->
      Process.put(retry_key, attempt)
    end

    resilience_stack =
      build_resilience_stack(
        transport,
        retry,
        rate_limiter,
        circuit_breaker,
        endpoint,
        context,
        before_attempt: before_attempt
      )

    opts = ensure_idempotency_key(endpoint, opts)

    try do
      result =
        with {:ok, {body, content_type}} <-
               encode_body(serializer, endpoint, payload, context, request_schema),
             result <-
               execute_with_retry(
                 resilience_stack,
                 retry_key,
                 endpoint,
                 body,
                 content_type,
                 context,
                 opts
               ),
             {:ok, %Response{} = response} <- normalize_transport_result(result) do
          {:ok, response}
        end

      handle_execute_result(
        result,
        serializer,
        response_schema,
        endpoint,
        telemetry,
        start_time,
        opts
      )
    after
      Process.delete(retry_key)
    end
  end

  defp handle_execute_result(
         {:ok, %Response{} = response},
         serializer,
         response_schema,
         endpoint,
         telemetry,
         start_time,
         opts
       ) do
    case handle_response(response, serializer, response_schema, endpoint, opts) do
      {:ok, data} ->
        emit_request_stop(telemetry, endpoint, response.status, start_time)
        {:ok, data}

      {:error, reason} = error ->
        emit_request_error(telemetry, endpoint, reason, start_time)
        error
    end
  end

  defp handle_execute_result(
         {:error, reason} = error,
         _serializer,
         _response_schema,
         endpoint,
         telemetry,
         start_time,
         _opts
       ) do
    emit_request_error(telemetry, endpoint, reason, start_time)
    error
  end

  defp emit_request_stop(telemetry, endpoint, status, start_time) do
    telemetry.emit(:request_stop, %{endpoint_id: endpoint.id, status: status}, %{
      duration_ms: System.monotonic_time(:millisecond) - start_time
    })
  end

  defp emit_request_error(telemetry, endpoint, reason, start_time) do
    telemetry.emit(:request_error, %{endpoint_id: endpoint.id, reason: reason}, %{
      duration_ms: System.monotonic_time(:millisecond) - start_time
    })
  end

  @doc """
  Execute a streaming endpoint and return a StreamResponse.

  This is used for SSE (Server-Sent Events) and other streaming endpoints
  where the response body is delivered incrementally.

  ## Parameters

    * `manifest` - The loaded manifest
    * `endpoint_id` - Endpoint identifier
    * `payload` - Request payload
    * `context` - Runtime context (must have `stream_transport` configured)
    * `opts` - Additional options (headers, query, path_params)

  ## Returns

    * `{:ok, StreamResponse.t()}` - Streaming response with enumerable events
    * `{:error, term()}` - Error during request setup or connection

  ## Example

      {:ok, response} = Pipeline.execute_stream(manifest, :sample_stream, payload, context)

      response.stream
      |> Stream.each(fn event ->
        IO.puts("Event: \#{event.data}")
      end)
      |> Stream.run()
  """
  @spec execute_stream(Manifest.t(), String.t() | atom(), term(), Context.t(), keyword()) ::
          {:ok, StreamResponse.t()} | {:error, term()}
  def execute_stream(
        %Manifest{} = manifest,
        endpoint_id,
        payload,
        %Context{} = context,
        opts \\ []
      ) do
    endpoint = Manifest.fetch_endpoint!(manifest, endpoint_id)

    serializer = context.serializer || raise ArgumentError, "serializer is required"

    stream_transport =
      context.stream_transport || raise ArgumentError, "stream_transport is required"

    telemetry = context.telemetry || Pristine.Adapters.Telemetry.Noop

    request_schema = Map.get(context.type_schemas, endpoint.request)

    telemetry.emit(:stream_start, %{endpoint_id: endpoint.id}, %{})
    start_time = System.monotonic_time(:millisecond)

    with {:ok, {body, content_type}} <-
           encode_body(serializer, endpoint, payload, context, request_schema),
         request <- build_request(endpoint, body, content_type, context, opts),
         {:ok, %StreamResponse{} = response} <- stream_transport.stream(request, context) do
      # Add timing metadata to the response
      response_with_metadata = %{
        response
        | metadata: Map.put(response.metadata, :start_time, start_time)
      }

      telemetry.emit(
        :stream_connected,
        %{endpoint_id: endpoint.id, status: response.status},
        %{duration_ms: System.monotonic_time(:millisecond) - start_time}
      )

      {:ok, response_with_metadata}
    else
      {:error, reason} = error ->
        stop_time = System.monotonic_time(:millisecond)

        telemetry.emit(:stream_error, %{endpoint_id: endpoint.id, reason: reason}, %{
          duration_ms: stop_time - start_time
        })

        error
    end
  end

  @doc """
  Execute a request and poll for a future result.

  This is used for long-running operations where the server returns
  a request ID that can be polled for the final result.

  ## Parameters

    * `manifest` - The loaded manifest
    * `endpoint_id` - Endpoint identifier for the initial request
    * `payload` - Request payload
    * `context` - Runtime context (must have `future` adapter configured)
    * `opts` - Additional options including future polling options

  ## Future Options

    * `:poll_interval_ms` - Base interval between polls (default: 1000)
    * `:max_poll_time_ms` - Maximum polling duration (default: 300000)
    * `:backoff` - Backoff strategy: `:none`, `:linear`, `:exponential`

  ## Returns

    * `{:ok, Task.t()}` - A task that will resolve to the final result
    * `{:error, term()}` - Error during initial request

  ## Example

      {:ok, task} = Pipeline.execute_future(manifest, :long_operation, payload, context)
      {:ok, result} = Future.await(task, 600_000)
  """
  @spec execute_future(Manifest.t(), String.t() | atom(), term(), Context.t(), keyword()) ::
          {:ok, Task.t()} | {:error, term()}
  def execute_future(
        %Manifest{} = manifest,
        endpoint_id,
        payload,
        %Context{} = context,
        opts \\ []
      ) do
    endpoint = Manifest.fetch_endpoint!(manifest, endpoint_id)
    future = context.future || raise ArgumentError, "future adapter is required"

    future_opts =
      context.future_opts
      |> Keyword.merge(Keyword.get(opts, :future_opts, []))
      |> maybe_put_retrieve_endpoint(endpoint.poll_endpoint)

    # First, execute the initial request to get the request_id
    case execute(manifest, endpoint_id, payload, context, opts) do
      {:ok, %{"request_id" => request_id}} ->
        future.poll(request_id, context, future_opts)

      {:ok, %{request_id: request_id}} ->
        future.poll(request_id, context, future_opts)

      {:ok, response} ->
        # Response doesn't contain a request_id - return it directly
        {:ok, Task.async(fn -> {:ok, response} end)}

      {:error, _} = error ->
        error
    end
  end

  defp maybe_put_retrieve_endpoint(opts, nil), do: opts

  defp maybe_put_retrieve_endpoint(opts, poll_endpoint),
    do: Keyword.put_new(opts, :retrieve_endpoint, poll_endpoint)

  defp build_resilience_stack(
         transport,
         retry,
         rate_limiter,
         circuit_breaker,
         endpoint,
         context,
         retry_overrides
       ) do
    cb_name = circuit_breaker_name(endpoint)
    cb_opts = context.circuit_breaker_opts
    rl_opts = rate_limit_opts(endpoint, context)
    rt_opts = retry_opts(endpoint, context) |> Keyword.merge(retry_overrides)

    fn request_or_fun ->
      retry.with_retry(
        fn ->
          request = resolve_request(request_or_fun)

          execute_with_resilience(
            transport,
            rate_limiter,
            circuit_breaker,
            request,
            context,
            cb_name,
            cb_opts,
            rl_opts
          )
        end,
        rt_opts
      )
    end
  end

  defp resolve_request(fun) when is_function(fun, 0), do: fun.()
  defp resolve_request(request), do: request

  defp execute_with_resilience(
         transport,
         rate_limiter,
         circuit_breaker,
         request,
         context,
         cb_name,
         cb_opts,
         rl_opts
       ) do
    rate_limiter.within_limit(
      fn ->
        circuit_breaker.call(cb_name, fn -> transport.send(request, context) end, cb_opts)
      end,
      rl_opts
    )
  end

  @doc false
  def build_request(endpoint, body, content_type, %Context{} = context, opts) do
    extra_headers =
      opts
      |> Keyword.get(:headers, %{})
      |> maybe_put_header("Last-Event-ID", Keyword.get(opts, :last_event_id))

    extra_query = Keyword.get(opts, :query, %{})
    path_params = Keyword.get(opts, :path_params, %{})
    query_opts = Keyword.merge(context.query_opts, Keyword.get(opts, :query_opts, []))
    retry_count = Keyword.get(opts, :retry_count, 0)
    timeout = Keyword.get(opts, :timeout) || endpoint.timeout

    auth_modules = resolve_auth(context.auth, endpoint.auth)

    package_version =
      context.package_version ||
        case Application.spec(:pristine, :vsn) do
          nil -> nil
          vsn -> List.to_string(vsn)
        end

    telemetry_headers =
      TelemetryHeaders.platform_headers(package_version: package_version)
      |> Map.merge(TelemetryHeaders.retry_headers(retry_count, timeout))
      |> Map.merge(context.headers)

    headers =
      case Headers.build(
             telemetry_headers,
             endpoint.headers,
             auth_modules,
             extra_headers,
             content_type
           ) do
        {:ok, merged} -> merged
        {:error, reason} -> raise ArgumentError, "auth headers failed: #{inspect(reason)}"
      end

    headers = maybe_add_idempotency_header(headers, endpoint, context, opts)

    url =
      Url.build(
        context.base_url,
        endpoint.path,
        path_params,
        Map.merge(endpoint.query, extra_query),
        query_opts
      )

    %Request{
      method: endpoint.method,
      url: url,
      headers: headers,
      body: body,
      endpoint_id: endpoint.id,
      metadata: %{endpoint: endpoint}
    }
  end

  defp retry_opts(%{retry: nil}, %Context{retry_opts: opts}), do: opts

  defp retry_opts(endpoint, %Context{retry_policies: policies, retry_opts: opts}) do
    policy = Map.get(policies, endpoint.retry, [])
    policy_opts = if is_map(policy), do: Map.to_list(policy), else: policy
    Keyword.merge(opts, policy_opts)
  end

  defp rate_limit_opts(%{rate_limit: nil}, %Context{rate_limit_opts: opts}), do: opts

  defp rate_limit_opts(endpoint, %Context{rate_limit_opts: opts}) do
    Keyword.put(opts, :key, endpoint.rate_limit || endpoint.id)
  end

  defp circuit_breaker_name(endpoint) do
    endpoint.circuit_breaker || endpoint.id
  end

  defp encode_body(serializer, endpoint, payload, %Context{} = context, request_schema) do
    body_type = normalize_body_type(endpoint.body_type)

    case body_type do
      :multipart ->
        multipart = context.multipart || raise ArgumentError, "multipart adapter is required"
        {content_type, body} = multipart.encode(payload, context.multipart_opts)
        {:ok, {body, content_type}}

      :json ->
        with {:ok, body} <- serializer.encode(payload, schema: request_schema) do
          {:ok, {body, endpoint.content_type || "application/json"}}
        end

      :raw ->
        {:ok, {payload, endpoint.content_type}}
    end
  end

  defp maybe_add_idempotency_header(headers, %{idempotency: true} = endpoint, context, opts) do
    header_name =
      endpoint.idempotency_header || context.idempotency_header || "X-Idempotency-Key"

    key = Keyword.get(opts, :idempotency_key) || UUID.uuid4()
    Map.put(headers, header_name, key)
  end

  defp maybe_add_idempotency_header(headers, _endpoint, _context, _opts), do: headers

  defp maybe_put_header(headers, _key, nil), do: headers
  defp maybe_put_header(headers, key, value), do: Map.put(headers, key, value)

  defp normalize_body_type(nil), do: :json
  defp normalize_body_type("multipart"), do: :multipart
  defp normalize_body_type("multipart/form-data"), do: :multipart
  defp normalize_body_type("raw"), do: :raw
  defp normalize_body_type(_), do: :json

  defp resolve_auth(auth, nil) when is_list(auth), do: auth
  defp resolve_auth(auth, nil) when is_map(auth), do: Map.get(auth, "default", [])
  defp resolve_auth(auth, key) when is_map(auth), do: Map.get(auth, to_string(key), [])
  defp resolve_auth(auth, _key) when is_list(auth), do: auth
  defp resolve_auth(_auth, _key), do: []

  defp normalize_transport_result({:ok, %Response{} = response}), do: {:ok, response}
  defp normalize_transport_result({:error, _} = error), do: error
  defp normalize_transport_result(other), do: {:error, other}

  defp normalize_decode_result({:ok, data}), do: {:ok, data}
  defp normalize_decode_result({:error, _} = error), do: error
  defp normalize_decode_result(data), do: {:ok, data}

  defp ensure_idempotency_key(%{idempotency: true} = endpoint, opts) do
    header = endpoint.idempotency_header || "X-Idempotency-Key"

    if Keyword.has_key?(opts, :idempotency_key) do
      opts
    else
      Keyword.put(opts, :idempotency_key, UUID.uuid4())
      |> Keyword.put(:idempotency_header, header)
    end
  end

  defp ensure_idempotency_key(_endpoint, opts), do: opts

  defp execute_with_retry(
         resilience_stack,
         retry_key,
         endpoint,
         body,
         content_type,
         context,
         opts
       ) do
    base_retry_count = Keyword.get(opts, :retry_count, 0)

    resilience_stack.(fn ->
      attempt = Process.get(retry_key, 0)
      retry_count = base_retry_count + attempt

      build_request(
        endpoint,
        body,
        content_type,
        context,
        Keyword.put(opts, :retry_count, retry_count)
      )
    end)
  end

  defp handle_response(
         %Response{status: status} = response,
         serializer,
         response_schema,
         endpoint,
         opts
       ) do
    if success_status?(status) do
      with {:ok, decoded} <- decode_body(serializer, response.body, opts),
           unwrapped <- unwrap_response(decoded, endpoint) do
        validate_response_schema(unwrapped, response_schema, opts)
      end
    else
      case decode_body(serializer, response.body, opts) do
        {:ok, decoded} ->
          error_response = %Response{response | body: decoded}
          {:error, Pristine.Error.from_response(error_response)}

        {:error, _} = error ->
          error
      end
    end
  end

  defp decode_body(serializer, body, opts) do
    decoded = serializer.decode(body, nil, opts)
    normalize_decode_result(decoded)
  end

  defp unwrap_response(body, %{response_unwrap: nil}), do: body

  defp unwrap_response(body, %{response_unwrap: path}) when is_binary(path) do
    keys = String.split(path, ".", trim: true)

    case get_in(body, keys) do
      nil -> body
      value -> value
    end
  end

  defp validate_response_schema(data, nil, _opts), do: {:ok, data}

  defp validate_response_schema(data, %Sinter.Schema{} = schema, opts) do
    Sinter.Validator.validate(schema, data, opts)
  end

  defp validate_response_schema(data, type_spec, opts) do
    path = Keyword.get(opts, :path, [])
    coerce = Keyword.get(opts, :coerce, false)

    if coerce do
      with {:ok, coerced} <- Sinter.Types.coerce(type_spec, data) do
        Sinter.Types.validate(type_spec, coerced, path)
      end
    else
      Sinter.Types.validate(type_spec, data, path)
    end
  end

  defp success_status?(status) when is_integer(status), do: status >= 200 and status < 300
  defp success_status?(_status), do: false
end
