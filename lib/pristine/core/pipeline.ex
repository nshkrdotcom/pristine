defmodule Pristine.Core.Pipeline do
  @moduledoc """
  Execute manifest-defined endpoints through the request pipeline.
  """

  alias Pristine.Core.{Context, Headers, Request, Response, Url}
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

    resilience_stack =
      build_resilience_stack(
        transport,
        retry,
        rate_limiter,
        circuit_breaker,
        endpoint,
        context
      )

    with {:ok, {body, content_type}} <-
           encode_body(serializer, endpoint, payload, context, request_schema),
         request <- build_request(endpoint, body, content_type, context, opts),
         result <- resilience_stack.(request),
         {:ok, %Response{} = response} <- normalize_transport_result(result),
         decoded <- serializer.decode(response.body, response_schema, opts),
         {:ok, data} <- normalize_decode_result(decoded) do
      stop_time = System.monotonic_time(:millisecond)

      telemetry.emit(:request_stop, %{endpoint_id: endpoint.id, status: response.status}, %{
        duration_ms: stop_time - start_time
      })

      {:ok, data}
    else
      {:error, reason} = error ->
        stop_time = System.monotonic_time(:millisecond)

        telemetry.emit(:request_error, %{endpoint_id: endpoint.id, reason: reason}, %{
          duration_ms: stop_time - start_time
        })

        error
    end
  end

  defp build_resilience_stack(transport, retry, rate_limiter, circuit_breaker, endpoint, context) do
    cb_name = circuit_breaker_name(endpoint)
    cb_opts = context.circuit_breaker_opts
    rl_opts = rate_limit_opts(endpoint, context)
    rt_opts = retry_opts(endpoint, context)

    fn request ->
      retry.with_retry(
        fn ->
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
    extra_headers = Keyword.get(opts, :headers, %{})
    extra_query = Keyword.get(opts, :query, %{})
    path_params = Keyword.get(opts, :path_params, %{})

    auth_modules = resolve_auth(context.auth, endpoint.auth)

    headers =
      case Headers.build(
             context.headers,
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
        Map.merge(endpoint.query, extra_query)
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

  defp maybe_add_idempotency_header(headers, %{idempotency: true}, context, opts) do
    header_name = context.idempotency_header || "X-Idempotency-Key"
    key = Keyword.get(opts, :idempotency_key) || UUID.uuid4()
    Map.put(headers, header_name, key)
  end

  defp maybe_add_idempotency_header(headers, _endpoint, _context, _opts), do: headers

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
end
