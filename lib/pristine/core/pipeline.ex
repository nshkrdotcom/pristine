defmodule Pristine.Core.Pipeline do
  @moduledoc """
  Execute manifest-defined endpoints through the request pipeline.

  Provides both synchronous (`execute/5`) and streaming (`execute_stream/5`)
  execution modes for manifest-defined API endpoints.
  """

  require Logger

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

    telemetry_metadata = build_telemetry_metadata(context, endpoint, opts)
    start_time = System.monotonic_time()

    telemetry.emit(
      telemetry_event(context, :request_start),
      telemetry_metadata,
      %{system_time: System.system_time()}
    )

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
        opts,
        before_attempt: before_attempt
      )

    opts = ensure_idempotency_key(endpoint, opts)

    try do
      result =
        with {:ok, {body, content_type}} <-
               encode_body(serializer, endpoint, payload, context, request_schema, opts),
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

      telemetry_state = %{
        context: context,
        telemetry: telemetry,
        metadata: telemetry_metadata,
        start_time: start_time,
        retry_key: retry_key,
        opts: opts
      }

      handle_execute_result(result, serializer, response_schema, endpoint, telemetry_state)
    rescue
      exception ->
        emit_request_exception(
          telemetry,
          context,
          telemetry_metadata,
          exception,
          __STACKTRACE__,
          start_time,
          retry_key
        )

        reraise exception, __STACKTRACE__
    after
      Process.delete(retry_key)
    end
  end

  defp handle_execute_result(
         {:ok, %Response{} = response},
         serializer,
         response_schema,
         endpoint,
         %{
           context: context,
           telemetry: telemetry,
           metadata: telemetry_metadata,
           start_time: start_time,
           retry_key: retry_key,
           opts: opts
         }
       ) do
    case handle_response(response, serializer, response_schema, endpoint, context, opts) do
      {:ok, data} ->
        retry_count = current_retry_count(retry_key)

        emit_request_stop(
          telemetry,
          context,
          telemetry_metadata,
          response.status,
          start_time,
          retry_count,
          :ok
        )

        {:ok, maybe_wrap_response(context, response, data, start_time, retry_count, opts)}

      {:error, reason} = error ->
        retry_count = current_retry_count(retry_key)

        emit_request_stop(
          telemetry,
          context,
          telemetry_metadata,
          response.status,
          start_time,
          retry_count,
          :error,
          reason
        )

        error
    end
  end

  defp handle_execute_result(
         {:error, reason} = error,
         _serializer,
         _response_schema,
         _endpoint,
         %{
           context: context,
           telemetry: telemetry,
           metadata: telemetry_metadata,
           start_time: start_time,
           retry_key: retry_key
         }
       ) do
    retry_count = current_retry_count(retry_key)

    error =
      if error_module?(context) do
        {:error, connection_error(context, reason)}
      else
        error
      end

    emit_request_stop(
      telemetry,
      context,
      telemetry_metadata,
      nil,
      start_time,
      retry_count,
      :error,
      reason
    )

    error
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

    telemetry_metadata = build_telemetry_metadata(context, endpoint, opts)

    telemetry.emit(
      telemetry_event(context, :stream_start),
      telemetry_metadata,
      %{system_time: System.system_time()}
    )

    start_time = System.monotonic_time()

    with {:ok, {body, content_type}} <-
           encode_body(serializer, endpoint, payload, context, request_schema, opts),
         request <- build_request(endpoint, body, content_type, context, opts),
         {:ok, %StreamResponse{} = response} <- stream_transport.stream(request, context) do
      # Add timing metadata to the response
      response_with_metadata = %{
        response
        | metadata: Map.put(response.metadata, :start_time, start_time)
      }

      telemetry.emit(
        telemetry_event(context, :stream_connected),
        Map.merge(telemetry_metadata, %{status: response.status, result: :ok}),
        %{duration: System.monotonic_time() - start_time}
      )

      {:ok, response_with_metadata}
    else
      {:error, reason} = error ->
        telemetry.emit(
          telemetry_event(context, :stream_error),
          Map.merge(telemetry_metadata, %{result: :error, reason: reason}),
          %{duration: System.monotonic_time() - start_time}
        )

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
         opts,
         retry_overrides
       ) do
    cb_name = circuit_breaker_name(endpoint)
    cb_opts = context.circuit_breaker_opts
    rl_opts = rate_limit_opts(endpoint, context)
    rt_opts = retry_opts(endpoint, context, opts) |> Keyword.merge(retry_overrides)

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
        execute_with_circuit_breaker(
          circuit_breaker,
          transport,
          request,
          context,
          cb_name,
          cb_opts
        )
      end,
      rl_opts
    )
  end

  defp execute_with_circuit_breaker(
         circuit_breaker,
         transport,
         request,
         context,
         cb_name,
         cb_opts
       ) do
    circuit_breaker.call(cb_name, fn -> send_request(transport, request, context) end, cb_opts)
  end

  defp send_request(transport, request, context) do
    case transport.send(request, context) do
      {:ok, %Response{} = response} ->
        {:ok, %Response{response | metadata: request.metadata}}

      other ->
        other
    end
  end

  @doc false
  def build_request(endpoint, body, content_type, %Context{} = context, opts) do
    path = Keyword.get(opts, :path, endpoint.path)

    extra_headers =
      opts
      |> Keyword.get(:headers, %{})
      |> normalize_header_map()
      |> Map.merge(build_extra_headers(context, endpoint, opts) |> normalize_header_map())
      |> maybe_put_header("Last-Event-ID", Keyword.get(opts, :last_event_id))

    extra_query = Keyword.get(opts, :query, %{})
    path_params = Keyword.get(opts, :path_params, %{})
    query_opts = Keyword.merge(context.query_opts, Keyword.get(opts, :query_opts, []))
    retry_count = Keyword.get(opts, :retry_count, 0)
    timeout = Keyword.get(opts, :timeout) || context.default_timeout || endpoint.timeout

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

    pool_type = resolve_pool_type(endpoint, opts)
    pool_name = resolve_pool_name(context, pool_type)

    url =
      Url.build(
        context.base_url,
        path,
        path_params,
        merge_query(context.default_query, endpoint.query, extra_query),
        query_opts
      )

    %Request{
      method: endpoint.method,
      url: url,
      headers: headers,
      body: body,
      endpoint_id: endpoint.id,
      metadata: %{
        endpoint: endpoint,
        pool_type: pool_type,
        pool_name: pool_name,
        method: endpoint.method,
        path: path,
        base_url: context.base_url,
        url: url
      }
    }
  end

  defp normalize_header_map(headers) when is_map(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_header_map(headers) when is_list(headers) do
    if Enum.all?(headers, &match?({_, _}, &1)) do
      Map.new(headers, fn {key, value} -> {to_string(key), value} end)
    else
      %{}
    end
  end

  defp normalize_header_map(_headers), do: %{}

  defp build_extra_headers(%Context{extra_headers: fun} = context, endpoint, opts)
       when is_function(fun, 3) do
    fun.(endpoint, context, opts)
  end

  defp build_extra_headers(%Context{extra_headers: fun}, endpoint, opts)
       when is_function(fun, 2) do
    fun.(endpoint, opts)
  end

  defp build_extra_headers(%Context{extra_headers: fun}, _endpoint, opts)
       when is_function(fun, 1) do
    fun.(opts)
  end

  defp build_extra_headers(_context, _endpoint, _opts), do: %{}

  defp merge_query(default_query, endpoint_query, extra_query) do
    normalize_query_map(default_query)
    |> Map.merge(normalize_query_map(endpoint_query))
    |> Map.merge(normalize_query_map(extra_query))
  end

  defp normalize_query_map(nil), do: %{}

  defp normalize_query_map(query) when is_map(query) do
    query
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp normalize_query_map(query) when is_list(query) do
    if Enum.all?(query, &match?({_, _}, &1)) do
      query
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Map.new()
    else
      %{}
    end
  end

  defp normalize_query_map(_), do: %{}

  defp resolve_pool_type(endpoint, opts) do
    opts
    |> Keyword.get(:pool_type, endpoint.resource || :default)
    |> normalize_pool_type()
  end

  defp normalize_pool_type(value) when is_atom(value), do: value

  defp normalize_pool_type(value) when is_binary(value) do
    String.to_atom(value)
  end

  defp normalize_pool_type(_), do: :default

  defp resolve_pool_name(
         %Context{pool_manager: manager, pool_base: pool_base, base_url: base_url},
         pool_type
       )
       when is_atom(manager) and not is_nil(pool_base) and is_binary(base_url) do
    manager.resolve_pool_name(pool_base, base_url, pool_type)
  end

  defp resolve_pool_name(_context, _pool_type), do: nil

  defp retry_opts(%{retry: nil}, %Context{} = context, opts) do
    apply_request_retry_opts(context.retry_opts, context, opts)
  end

  defp retry_opts(
         endpoint,
         %Context{retry_policies: policies, retry_opts: base_opts} = context,
         opts
       ) do
    policy = Map.get(policies, endpoint.retry, [])
    policy_opts = normalize_retry_policy_opts(policy)

    base_opts
    |> Keyword.merge(policy_opts)
    |> apply_request_retry_opts(context, opts)
  end

  defp normalize_retry_policy_opts(nil), do: []
  defp normalize_retry_policy_opts(policy) when is_list(policy), do: policy
  defp normalize_retry_policy_opts(policy) when is_map(policy), do: Map.to_list(policy)
  defp normalize_retry_policy_opts(_), do: []

  defp apply_request_retry_opts(base_opts, %Context{} = context, opts) do
    merged =
      (base_opts || [])
      |> Keyword.merge(Keyword.get(opts, :retry_opts, []))

    max_retries =
      normalize_max_retries(Keyword.get(opts, :max_retries, Keyword.get(merged, :max_retries)))

    maybe_put_retry_policy(merged, context, max_retries)
  end

  defp maybe_put_retry_policy(merged, _context, nil), do: merged

  defp maybe_put_retry_policy(merged, context, max_retries) do
    if Keyword.has_key?(merged, :policy) do
      merged
    else
      case build_http_retry_policy(context, max_retries, merged) do
        nil -> merged
        policy -> Keyword.put(Keyword.delete(merged, :max_retries), :policy, policy)
      end
    end
  end

  defp normalize_max_retries(nil), do: nil

  defp normalize_max_retries(value) when is_integer(value) and value >= 0, do: value

  defp normalize_max_retries(_), do: nil

  defp build_http_retry_policy(%Context{retry: retry}, max_retries, opts) do
    if is_atom(retry) and function_exported?(retry, :build_policy, 1) and
         function_exported?(retry, :build_backoff, 1) do
      backoff = build_backoff(retry, opts)

      policy_opts =
        opts
        |> Keyword.put(:max_attempts, max_retries)
        |> Keyword.put(:backoff, backoff)
        |> Keyword.put(:retry_on, &http_retry_on(retry, &1))
        |> Keyword.put(:retry_after_ms_fun, &http_retry_after_ms(retry, &1))

      retry.build_policy(policy_opts)
    else
      nil
    end
  end

  defp build_backoff(retry, opts) do
    case Keyword.get(opts, :backoff) do
      nil ->
        backoff_opts = Keyword.get(opts, :backoff_opts, default_backoff_opts())
        retry.build_backoff(backoff_opts)

      backoff ->
        backoff
    end
  end

  defp default_backoff_opts do
    [
      strategy: :exponential,
      base_ms: 500,
      max_ms: 10_000,
      jitter_strategy: :factor,
      jitter: 0.25
    ]
  end

  defp http_retry_on(retry, {:ok, response}) do
    if function_exported?(retry, :should_retry?, 1) do
      retry.should_retry?(response)
    else
      false
    end
  end

  defp http_retry_on(_retry, {:error, %Mint.TransportError{}}), do: true
  defp http_retry_on(_retry, {:error, %Mint.HTTPError{}}), do: true
  defp http_retry_on(_retry, {:error, :timeout}), do: true
  defp http_retry_on(_retry, _result), do: false

  defp http_retry_after_ms(retry, {:ok, %{headers: headers}}) do
    if function_exported?(retry, :parse_retry_after, 1) do
      retry.parse_retry_after(%{headers: headers})
    end
  end

  defp http_retry_after_ms(_retry, _result), do: nil

  defp rate_limit_opts(%{rate_limit: nil}, %Context{rate_limit_opts: opts}), do: opts

  defp rate_limit_opts(endpoint, %Context{rate_limit_opts: opts}) do
    Keyword.put(opts, :key, endpoint.rate_limit || endpoint.id)
  end

  defp circuit_breaker_name(endpoint) do
    endpoint.circuit_breaker || endpoint.id
  end

  defp encode_body(serializer, endpoint, payload, %Context{} = context, request_schema, opts) do
    body_type = normalize_body_type(Keyword.get(opts, :body_type, endpoint.body_type))
    transform_opts = merge_transform_opts(context.transform_opts, endpoint, opts, request_schema)

    case body_type do
      :multipart ->
        multipart = context.multipart || raise ArgumentError, "multipart adapter is required"
        payload = maybe_transform_payload(payload, transform_opts)
        {content_type, body} = multipart.encode(payload, context.multipart_opts)
        {:ok, {body, content_type}}

      :json ->
        payload = maybe_transform_payload(payload, transform_opts)

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

  defp merge_transform_opts(base_opts, endpoint, opts, request_schema) do
    context_opts = normalize_transform_opts(base_opts)
    endpoint_opts = normalize_transform_opts(Map.get(endpoint, :transform))
    request_opts = normalize_transform_opts(Keyword.get(opts, :transform))

    merged =
      context_opts
      |> Keyword.merge(endpoint_opts)
      |> Keyword.merge(request_opts)

    if request_schema && Keyword.get(merged, :use_aliases) do
      Keyword.put_new(merged, :schema, request_schema)
    else
      merged
    end
  end

  defp maybe_transform_payload(payload, []), do: payload

  defp maybe_transform_payload(payload, opts) when is_list(opts) do
    Sinter.Transform.transform(payload, opts)
  end

  defp normalize_transform_opts(nil), do: []

  defp normalize_transform_opts(opts) when is_map(opts) do
    Enum.map(opts, fn {key, value} ->
      {normalize_transform_key(key), value}
    end)
  end

  defp normalize_transform_opts(opts) when is_list(opts) do
    cond do
      Keyword.keyword?(opts) ->
        opts

      Enum.all?(opts, &match?([_, _], &1)) ->
        Enum.map(opts, fn [key, value] ->
          {normalize_transform_key(key), value}
        end)

      true ->
        []
    end
  end

  defp normalize_transform_key(key) when is_atom(key), do: key

  defp normalize_transform_key(key) when is_binary(key) do
    case key do
      "drop_nil?" -> :drop_nil?
      "drop_nil" -> :drop_nil?
      "aliases" -> :aliases
      "formats" -> :formats
      "use_aliases" -> :use_aliases
      "schema" -> :schema
      other -> other
    end
  end

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

      request =
        build_request(
          endpoint,
          body,
          content_type,
          context,
          Keyword.put(opts, :retry_count, retry_count)
        )

      maybe_dump_request(request, context, retry_count)
      request
    end)
  end

  defp maybe_dump_request(%Request{} = request, %Context{} = context, attempt) do
    if context.dump_headers? do
      redacted = redact_headers(request.headers, context)
      body_dump = dump_body(request.body)
      method = format_method(request.method)
      url = request.url

      Logger.info(
        "HTTP #{method} #{url} attempt=#{attempt} headers=#{inspect(redacted)} body=#{body_dump}"
      )
    end
  end

  defp dump_body(nil), do: "nil"

  defp dump_body(body) do
    IO.iodata_to_binary(body)
  rescue
    _ -> inspect(body)
  end

  defp redact_headers(headers, %Context{redact_headers: redactor})
       when is_function(redactor, 1) do
    redactor.(headers)
  end

  defp redact_headers(headers, _context) do
    Enum.map(headers, fn {name, value} ->
      lowered = String.downcase(to_string(name))

      if lowered in [
           "x-api-key",
           "cf-access-client-secret",
           "authorization",
           "proxy-authorization"
         ] do
        {name, "[REDACTED]"}
      else
        {name, value}
      end
    end)
  end

  defp format_method(method) when is_atom(method),
    do: method |> Atom.to_string() |> String.upcase()

  defp format_method(method) when is_binary(method) do
    method |> String.upcase()
  end

  defp format_method(method), do: method |> to_string() |> String.upcase()

  defp telemetry_event(%Context{telemetry_events: events}, key) when is_map(events) do
    Map.get(events, key, key)
  end

  defp telemetry_event(_context, key), do: key

  defp build_telemetry_metadata(%Context{} = context, endpoint, opts) do
    pool_type = resolve_pool_type(endpoint, opts)
    path = Keyword.get(opts, :path, endpoint.path)

    base =
      %{
        endpoint_id: endpoint.id,
        method: telemetry_method(endpoint.method),
        path: path,
        pool_type: pool_type,
        base_url: context.base_url
      }
      |> Map.merge(context.telemetry_metadata || %{})

    case Keyword.get(opts, :telemetry_metadata) do
      meta when is_map(meta) -> Map.merge(base, meta)
      _ -> base
    end
  end

  defp telemetry_method(method) when is_atom(method), do: method

  defp telemetry_method(method) when is_binary(method) do
    case String.downcase(method) do
      "get" -> :get
      "post" -> :post
      "put" -> :put
      "patch" -> :patch
      "delete" -> :delete
      "head" -> :head
      "options" -> :options
      other -> String.to_atom(other)
    end
  end

  defp telemetry_method(method), do: method

  defp emit_request_stop(
         telemetry,
         context,
         metadata,
         status,
         start_time,
         retry_count,
         result,
         reason \\ nil
       ) do
    metadata =
      metadata
      |> Map.put(:result, result)
      |> Map.put(:retry_count, retry_count)
      |> maybe_put_metadata(:status, status)
      |> maybe_put_metadata(:reason, reason)

    telemetry.emit(
      telemetry_event(context, :request_stop),
      metadata,
      %{duration: System.monotonic_time() - start_time}
    )
  end

  defp emit_request_exception(
         telemetry,
         context,
         metadata,
         exception,
         stacktrace,
         start_time,
         retry_key
       ) do
    event = telemetry_event(context, :request_exception)

    if event do
      retry_count = current_retry_count(retry_key)

      telemetry.emit(
        event,
        Map.merge(metadata, %{
          kind: :error,
          reason: exception,
          stacktrace: stacktrace,
          retry_count: retry_count,
          result: :error
        }),
        %{duration: System.monotonic_time() - start_time}
      )
    end
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp current_retry_count(retry_key) do
    case Process.get(retry_key) do
      count when is_integer(count) and count >= 0 -> count
      _ -> 0
    end
  end

  defp maybe_wrap_response(
         %Context{response_wrapper: wrapper},
         %Response{} = response,
         data,
         start_time,
         retry_count,
         opts
       )
       when is_atom(wrapper) do
    if Keyword.get(opts, :response) == :wrapped do
      elapsed_ms = System.monotonic_time() - start_time
      elapsed_ms = System.convert_time_unit(elapsed_ms, :native, :millisecond)

      wrapper_opts =
        [
          method: telemetry_method(response.metadata[:method] || response.metadata["method"]),
          url: response.metadata[:url],
          retries: retry_count,
          elapsed_ms: elapsed_ms,
          data: data
        ]

      cond do
        function_exported?(wrapper, :new, 2) -> wrapper.new(response, wrapper_opts)
        function_exported?(wrapper, :wrap, 2) -> wrapper.wrap(response, wrapper_opts)
        true -> data
      end
    else
      data
    end
  end

  defp maybe_wrap_response(_context, _response, data, _start_time, _retry_count, _opts), do: data

  defp handle_response(
         %Response{status: status} = response,
         serializer,
         response_schema,
         endpoint,
         %Context{} = context,
         opts
       ) do
    response =
      response
      |> normalize_response_body()
      |> decompress_response()

    cond do
      redirect_status?(status) ->
        handle_redirect_response(response, context, opts)

      success_status?(status) ->
        handle_success_response(response, serializer, response_schema, endpoint, context, opts)

      true ->
        handle_error_response(response, serializer, context, opts)
    end
  end

  defp decode_body(serializer, body, opts) do
    decoded = serializer.decode(body, nil, opts)
    normalize_decode_result(decoded)
  end

  defp handle_success_response(
         %Response{body: body},
         serializer,
         response_schema,
         endpoint,
         context,
         opts
       ) do
    case decode_body(serializer, body, opts) do
      {:ok, decoded} ->
        unwrapped = unwrap_response(decoded, endpoint)
        validate_response_schema(unwrapped, response_schema, opts)

      {:error, _} when body in [nil, ""] ->
        validate_response_schema(%{}, response_schema, opts)

      {:error, reason} ->
        if error_module?(context) do
          {:error, validation_error(context, reason, body)}
        else
          {:error, reason}
        end
    end
  end

  defp handle_error_response(%Response{} = response, serializer, context, opts) do
    case decode_body(serializer, response.body, opts) do
      {:ok, decoded} ->
        retry_after_ms = if error_module?(context), do: parse_retry_after(context, response)
        {:error, build_error(context, response, decoded, retry_after_ms, opts)}

      {:error, reason} ->
        if error_module?(context) do
          error_body = %{"message" => response.body}
          retry_after_ms = parse_retry_after(context, response)
          {:error, build_error(context, response, error_body, retry_after_ms, opts)}
        else
          {:error, reason}
        end
    end
  end

  defp handle_redirect_response(
         %Response{headers: headers, status: status} = response,
         context,
         _opts
       ) do
    case header_value(headers, "location") do
      nil ->
        {:error,
         validation_error(context, "redirect without location header", %{
           status: status,
           body: response.body
         })}

      location ->
        expires = header_value(headers, "expires")
        {:ok, %{"url" => location, "status" => status, "expires" => expires}}
    end
  end

  defp validation_error(%Context{error_module: error_module}, reason, body) do
    cond do
      is_atom(error_module) and function_exported?(error_module, :validation_error, 2) ->
        error_module.validation_error(reason, body)

      is_atom(error_module) and function_exported?(error_module, :new, 3) ->
        error_module.new(:validation, "JSON decode error: #{inspect(reason)}",
          category: :user,
          data: %{body: body}
        )

      true ->
        {:invalid_json, reason}
    end
  end

  defp error_module?(%Context{error_module: error_module}),
    do: is_atom(error_module) and not is_nil(error_module)

  defp build_error(
         %Context{error_module: error_module},
         %Response{} = response,
         body,
         retry_after_ms,
         opts
       ) do
    case error_module_arity(error_module) do
      {:ok, arity} ->
        invoke_error_module(error_module, arity, response, body, retry_after_ms, opts)

      :error ->
        Pristine.Error.from_response(%Response{response | body: body})
    end
  end

  defp error_module_arity(error_module) when is_atom(error_module) do
    arity =
      [4, 3, 2, 1]
      |> Enum.find(&function_exported?(error_module, :from_response, &1))

    if arity, do: {:ok, arity}, else: :error
  end

  defp error_module_arity(_), do: :error

  defp invoke_error_module(error_module, 4, response, body, retry_after_ms, opts) do
    error_module.from_response(response, body, retry_after_ms, opts)
  end

  defp invoke_error_module(error_module, 3, response, body, retry_after_ms, _opts) do
    error_module.from_response(response, body, retry_after_ms)
  end

  defp invoke_error_module(error_module, 2, response, body, _retry_after_ms, _opts) do
    error_module.from_response(response, body)
  end

  defp invoke_error_module(error_module, 1, response, _body, _retry_after_ms, _opts) do
    error_module.from_response(response)
  end

  defp connection_error(%Context{error_module: error_module}, reason) do
    cond do
      is_atom(error_module) and function_exported?(error_module, :connection_error, 1) ->
        error_module.connection_error(reason)

      is_atom(error_module) and function_exported?(error_module, :new, 3) ->
        error_module.new(:api_connection, format_error_reason(reason), data: %{exception: reason})

      true ->
        reason
    end
  end

  defp format_error_reason(reason) do
    cond do
      is_struct(reason) and function_exported?(reason.__struct__, :message, 1) ->
        Exception.message(reason)

      is_atom(reason) ->
        Atom.to_string(reason)

      is_binary(reason) ->
        reason

      true ->
        inspect(reason)
    end
  end

  defp parse_retry_after(%Context{retry: retry}, %Response{headers: headers}) do
    if is_atom(retry) and function_exported?(retry, :parse_retry_after, 1) do
      retry.parse_retry_after(%{headers: headers})
    end
  end

  defp normalize_response_body(%Response{body: body} = response) when is_binary(body),
    do: response

  defp normalize_response_body(%Response{body: body} = response) do
    %{response | body: IO.iodata_to_binary(body)}
  rescue
    _ -> response
  end

  defp decompress_response(%Response{headers: headers, body: body} = response) do
    case header_value(headers, "content-encoding") do
      "gzip" ->
        decoded =
          try do
            :zlib.gunzip(body)
          rescue
            _ -> body
          end

        %{response | body: decoded, headers: strip_header(headers, "content-encoding")}

      _ ->
        response
    end
  end

  defp redirect_status?(status) when status in [301, 302, 307, 308], do: true
  defp redirect_status?(_status), do: false

  defp header_value(headers, target) when is_list(headers) do
    target = String.downcase(target)

    Enum.find_value(headers, fn
      {key, value} ->
        if String.downcase(to_string(key)) == target do
          normalize_header_value(value)
        end

      _ ->
        nil
    end)
  end

  defp header_value(headers, target) when is_map(headers) do
    target = String.downcase(target)

    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == target do
        normalize_header_value(value)
      end
    end)
  end

  defp header_value(_headers, _target), do: nil

  defp normalize_header_value(value) when is_binary(value), do: String.trim(value)

  defp normalize_header_value(value) do
    value
    |> to_string()
    |> String.trim()
  end

  defp strip_header(headers, name) when is_map(headers) do
    target = String.downcase(name)

    headers
    |> Enum.reject(fn {key, _value} -> String.downcase(to_string(key)) == target end)
    |> Map.new()
  end

  defp strip_header(headers, name) when is_list(headers) do
    target = String.downcase(name)

    Enum.reject(headers, fn {key, _value} ->
      String.downcase(to_string(key)) == target
    end)
  end

  defp strip_header(headers, _name), do: headers

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
