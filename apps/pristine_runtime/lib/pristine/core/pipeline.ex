defmodule Pristine.Core.Pipeline do
  @moduledoc """
  Execute normalized request metadata through the shared request pipeline.
  """

  require Logger

  alias Pristine.Adapters.Auth.{Basic, Bearer}

  alias Pristine.Core.{
    Context,
    EndpointMetadata,
    Headers,
    HTTPMethod,
    PoolRouting,
    Request,
    RequestPath,
    Response,
    ResultClassification,
    StreamResponse,
    TelemetryHeaders,
    Url
  }

  alias Pristine.Operation
  alias Pristine.Runtime.Schema, as: RuntimeSchema

  @retry_policy_keys [
    :backoff,
    :base_ms,
    :jitter,
    :jitter_strategy,
    :max_attempts,
    :max_ms,
    :progress_timeout_ms,
    :retry_after_ms_fun,
    :retry_on,
    :strategy
  ]
  @retry_policy_string_keys Map.new(@retry_policy_keys, &{Atom.to_string(&1), &1})
  @backoff_keys [:base_ms, :jitter, :jitter_strategy, :max_ms, :strategy]
  @backoff_string_keys Map.new(@backoff_keys, &{Atom.to_string(&1), &1})
  @legacy_retry_keys [
    :backoff_opts,
    :base_delay_ms,
    :max_delay_ms,
    :max_retries,
    "backoff_opts",
    "base_delay_ms",
    "max_delay_ms",
    "max_retries"
  ]
  @backoff_strategy_aliases %{
    "constant" => :constant,
    "exponential" => :exponential,
    "linear" => :linear
  }
  @backoff_strategies Map.values(@backoff_strategy_aliases)
  @backoff_jitter_strategy_aliases %{
    "additive" => :additive,
    "factor" => :factor,
    "none" => :none,
    "range" => :range
  }
  @backoff_jitter_strategies Map.values(@backoff_jitter_strategy_aliases)
  @attempt_outcome_tag :pristine_attempt_outcome

  @doc false
  @spec execute_operation(Operation.t(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute_operation(%Operation{} = operation, %Context{} = context, opts \\ []) do
    {payload, body_type, content_type} =
      request_payload(%{body: operation.body, form_data: operation.form_data})

    endpoint =
      EndpointMetadata.from_operation(
        operation,
        body_type: body_type,
        content_type: content_type
      )

    execute_opts =
      opts
      |> Keyword.put(
        :path_params,
        merge_string_key_maps(operation.path_params, opts[:path_params])
      )
      |> maybe_put_new(:auth, operation_auth_override(operation))

    execute_endpoint(endpoint, payload, context, execute_opts)
  end

  @spec execute_endpoint(EndpointMetadata.t(), term(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute_endpoint(%EndpointMetadata{} = endpoint, payload, %Context{} = context, opts \\ []) do
    serializer = context.serializer || raise ArgumentError, "serializer is required"
    transport = context.transport || raise ArgumentError, "transport is required"
    retry = context.retry || Pristine.Adapters.Retry.Noop
    rate_limiter = context.rate_limiter || Pristine.Adapters.RateLimit.Noop
    circuit_breaker = context.circuit_breaker || Pristine.Adapters.CircuitBreaker.Foundation
    telemetry = context.telemetry || Pristine.Adapters.Telemetry.Noop

    request_schema = RuntimeSchema.resolve_schema(endpoint.request, context.type_schemas)
    response_ref = endpoint.response

    telemetry_metadata = build_telemetry_metadata(context, endpoint, opts)
    start_time = System.monotonic_time()

    telemetry.emit(
      telemetry_event(context, :request_start),
      telemetry_metadata,
      %{system_time: System.system_time()}
    )

    maybe_log(context, :info, "request start", telemetry_metadata)

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
             attempt_outcome <-
               execute_with_retry(
                 resilience_stack,
                 retry_key,
                 endpoint,
                 body,
                 content_type,
                 context,
                 opts
               ) do
          {normalize_transport_result(attempt_result(attempt_outcome)), attempt_outcome}
        end

      telemetry_state = %{
        context: context,
        telemetry: telemetry,
        metadata: telemetry_metadata,
        start_time: start_time,
        retry_key: retry_key,
        opts: opts
      }

      handle_execute_result(result, serializer, response_ref, endpoint, telemetry_state)
    rescue
      exception ->
        maybe_log(context, :error, "request fail", %{
          endpoint_id: endpoint.id,
          method: HTTPMethod.telemetry(endpoint.method),
          path: Keyword.get(opts, :path, endpoint.path),
          reason: log_reason(exception),
          retry_count: current_retry_count(retry_key)
        })

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

  @spec stream_operation(Operation.t(), Context.t(), keyword()) ::
          {:ok, Pristine.Response.t()} | {:error, term()}
  def stream_operation(%Operation{} = operation, %Context{} = context, opts \\ []) do
    stream_transport =
      context.stream_transport || raise ArgumentError, "stream_transport is required"

    serializer = context.serializer

    {payload, body_type, content_type} =
      request_payload(%{body: operation.body, form_data: operation.form_data})

    endpoint =
      EndpointMetadata.from_operation(
        operation,
        body_type: body_type,
        content_type: content_type
      )

    execute_opts =
      opts
      |> Keyword.put(
        :path_params,
        merge_string_key_maps(operation.path_params, opts[:path_params])
      )
      |> maybe_put_new(:auth, operation_auth_override(operation))

    request_schema = RuntimeSchema.resolve_schema(endpoint.request, context.type_schemas)

    with {:ok, {body, content_type}} <-
           encode_body(serializer, endpoint, payload, context, request_schema, execute_opts),
         %Request{} = request <-
           build_request(endpoint, body, content_type, context, execute_opts),
         {:ok, %StreamResponse{} = response} <- stream_transport.stream(request, context) do
      {:ok, Pristine.Response.from_stream(response)}
    end
  end

  defp handle_execute_result(
         {{:ok, %Response{} = response}, attempt_outcome},
         serializer,
         response_ref,
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
    classification = attempt_classification(attempt_outcome, context, endpoint, opts)
    telemetry_metadata = Map.merge(telemetry_metadata, classification.telemetry)

    case handle_response(response, serializer, response_ref, endpoint, context, opts) do
      {:ok, data} ->
        retry_count = current_retry_count(retry_key)

        maybe_log(
          context,
          :info,
          "request success",
          Map.merge(telemetry_metadata, %{
            status: response.status,
            retry_count: retry_count
          })
        )

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

        maybe_log(
          context,
          :warn,
          "request fail",
          Map.merge(telemetry_metadata, %{
            status: response.status,
            reason: log_reason(reason),
            retry_count: retry_count
          })
        )

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
         {{:error, reason} = error, attempt_outcome},
         _serializer,
         _response_ref,
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
    classification = attempt_classification(attempt_outcome, context, endpoint, opts)
    telemetry_metadata = Map.merge(telemetry_metadata, classification.telemetry)
    retry_count = current_retry_count(retry_key)

    error =
      if error_module?(context) do
        if validation_reason?(reason) do
          {:error, validation_error(context, reason, nil)}
        else
          {:error, connection_error(context, reason)}
        end
      else
        error
      end

    maybe_log(
      context,
      :warn,
      "request fail",
      Map.merge(telemetry_metadata, %{
        reason: log_reason(reason),
        retry_count: retry_count
      })
    )

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

  defp handle_execute_result(
         {:error, reason} = error,
         _serializer,
         _response_ref,
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
    classification = classify_result(context, error, endpoint, opts)
    telemetry_metadata = Map.merge(telemetry_metadata, classification.telemetry)
    retry_count = current_retry_count(retry_key)

    error =
      if error_module?(context) do
        if validation_reason?(reason) do
          {:error, validation_error(context, reason, nil)}
        else
          {:error, connection_error(context, reason)}
        end
      else
        error
      end

    maybe_log(
      context,
      :warn,
      "request fail",
      Map.merge(telemetry_metadata, %{
        reason: log_reason(reason),
        retry_count: retry_count
      })
    )

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
    admission_control = context.admission_control || Pristine.Adapters.AdmissionControl.Noop
    cb_name = circuit_breaker_name(endpoint)
    cb_opts = context.circuit_breaker_opts
    rl_opts = rate_limit_opts(endpoint, context)
    rt_opts = retry_opts(endpoint, context, opts) |> Keyword.merge(retry_overrides)

    fn request_or_fun ->
      retry.with_retry(
        fn ->
          request = resolve_request(request_or_fun)

          resilience = %{
            endpoint: endpoint,
            context: context,
            cb_name: cb_name,
            cb_opts: cb_opts,
            rl_opts: rl_opts,
            request_opts: opts
          }

          execute_with_resilience(
            admission_control,
            transport,
            rate_limiter,
            circuit_breaker,
            request,
            resilience
          )
        end,
        rt_opts
      )
    end
  end

  defp resolve_request(fun) when is_function(fun, 0), do: fun.()
  defp resolve_request(request), do: request

  defp request_payload(%{form_data: form_data} = request_spec) when is_map(form_data) do
    if map_size(form_data) > 0 do
      {form_data, "multipart", nil}
    else
      request_payload(%{request_spec | form_data: nil})
    end
  end

  defp request_payload(%{body: nil}), do: {nil, "raw", nil}

  defp request_payload(%{body: body}) when is_map(body),
    do: {body, nil, "application/json"}

  defp request_payload(%{body: body}), do: {body, "raw", nil}

  defp normalize_string_key_map(nil), do: %{}

  defp normalize_string_key_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_string_key_map(map) when is_list(map) do
    if Keyword.keyword?(map) do
      Map.new(map, fn {key, value} -> {to_string(key), value} end)
    else
      %{}
    end
  end

  defp normalize_string_key_map(_map), do: %{}

  defp merge_string_key_maps(base, override) do
    Map.merge(base, normalize_string_key_map(override))
  end

  defp operation_auth_override(%Operation{auth: %{override: override}})
       when not is_nil(override),
       do: override

  defp operation_auth_override(%Operation{auth: %{use_client_default?: false}}), do: []
  defp operation_auth_override(_operation), do: nil

  defp execute_with_resilience(
         admission_control,
         transport,
         rate_limiter,
         circuit_breaker,
         request,
         %{endpoint: endpoint, context: context, request_opts: opts} = resilience
       ) do
    cb_name = resilience.cb_name
    cb_opts = resilience.cb_opts
    rl_opts = resilience.rl_opts
    admission_opts = admission_opts(request, endpoint, context)

    admission_control.with_admission(
      fn ->
        rate_limiter.within_limit(
          fn ->
            attempt_outcome =
              execute_with_circuit_breaker(
                circuit_breaker,
                transport,
                request,
                endpoint,
                context,
                cb_name,
                cb_opts,
                opts
              )

            maybe_apply_limiter_backoff(
              rate_limiter,
              attempt_outcome,
              endpoint,
              context,
              rl_opts,
              opts
            )

            maybe_apply_admission_backoff(
              admission_control,
              attempt_outcome,
              endpoint,
              context,
              admission_opts,
              opts
            )

            attempt_outcome
          end,
          rl_opts
        )
      end,
      admission_opts
    )
  end

  defp execute_with_circuit_breaker(
         circuit_breaker,
         transport,
         request,
         endpoint,
         context,
         cb_name,
         cb_opts,
         opts
       ) do
    cb_opts =
      Keyword.put(
        cb_opts,
        :success?,
        fn result ->
          attempt_classification(result, context, endpoint, opts).breaker_outcome
        end
      )

    case circuit_breaker.call(
           cb_name,
           fn ->
             result = send_request(transport, request, context)
             classification = classify_result(context, result, endpoint, opts)
             attempt_outcome(result, classification)
           end,
           cb_opts
         ) do
      {@attempt_outcome_tag, _result, _classification} = attempt_outcome ->
        attempt_outcome

      result ->
        attempt_outcome(result, classify_result(context, result, endpoint, opts))
    end
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
    timeout = Keyword.get(opts, :timeout) || endpoint.timeout || context.default_timeout

    RequestPath.validate!(path)
    RequestPath.validate_path_params!(path_params)

    auth_modules =
      resolve_auth(context.auth, endpoint.security, Keyword.fetch(opts, :auth))

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

    pool_type = PoolRouting.resolve_type(endpoint, opts)
    pool_name = PoolRouting.resolve_name(context, pool_type)

    url =
      Url.build(
        context.base_url,
        path,
        path_params,
        merge_query(context.default_query, endpoint.query, extra_query),
        query_opts
      )

    metadata =
      %{
        endpoint: endpoint,
        pool_type: pool_type,
        method: endpoint.method,
        path: path,
        base_url: context.base_url,
        url: url,
        timeout: timeout
      }
      |> maybe_put_metadata(:pool_name, pool_name)

    %Request{
      method: endpoint.method,
      url: url,
      headers: headers,
      body: body,
      endpoint_id: endpoint.id,
      metadata: metadata
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

  defp maybe_put_new(opts, _key, nil), do: opts

  defp maybe_put_new(opts, key, value) do
    if Keyword.has_key?(opts, key) do
      opts
    else
      Keyword.put(opts, key, value)
    end
  end

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

  defp retry_opts(%{retry: nil} = endpoint, %Context{} = context, opts) do
    apply_request_retry_opts(context.retry_opts, endpoint, context, opts)
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
    |> apply_request_retry_opts(endpoint, context, opts)
  end

  defp normalize_retry_policy_opts(nil), do: []

  defp normalize_retry_policy_opts(policy) when is_list(policy) or is_map(policy) do
    policy
    |> Enum.reduce([], fn entry, acc ->
      [normalize_retry_policy_entry(entry) | acc]
    end)
    |> Enum.reverse()
  end

  defp normalize_retry_policy_opts(_), do: []

  defp normalize_retry_policy_entry({key, value}) do
    atom_key = normalize_retry_policy_key(key)
    {atom_key, normalize_retry_policy_value(atom_key, value)}
  end

  defp normalize_retry_policy_key(key) when is_atom(key) do
    cond do
      key in @retry_policy_keys -> key
      key in @legacy_retry_keys -> raise_legacy_retry_key!(key)
      true -> raise_unknown_retry_key!(key)
    end
  end

  defp normalize_retry_policy_key(key) when is_binary(key) do
    cond do
      Map.has_key?(@retry_policy_string_keys, key) -> Map.fetch!(@retry_policy_string_keys, key)
      key in @legacy_retry_keys -> raise_legacy_retry_key!(key)
      true -> raise_unknown_retry_key!(key)
    end
  end

  defp normalize_retry_policy_key(key), do: raise_unknown_retry_key!(key)

  defp normalize_retry_policy_value(:backoff, value), do: normalize_backoff_value(value)

  defp normalize_retry_policy_value(:jitter_strategy, value),
    do: normalize_backoff_jitter_strategy(value) || value

  defp normalize_retry_policy_value(:strategy, value),
    do: normalize_backoff_strategy(value) || value

  defp normalize_retry_policy_value(_key, value), do: value

  defp apply_request_retry_opts(base_opts, endpoint, %Context{} = context, opts) do
    merged =
      (base_opts || [])
      |> Keyword.merge(Keyword.get(opts, :retry_opts, []))

    reject_legacy_retry_keys!(merged)

    max_attempts =
      opts
      |> Keyword.get(:max_attempts, Keyword.get(merged, :max_attempts))
      |> normalize_retry_attempts()

    maybe_put_retry_policy(merged, endpoint, context, opts, max_attempts)
  end

  defp maybe_put_retry_policy(merged, _endpoint, _context, _opts, nil), do: merged

  defp maybe_put_retry_policy(merged, endpoint, context, opts, max_attempts) do
    if Keyword.has_key?(merged, :policy) do
      merged
    else
      case build_http_retry_policy(context, endpoint, opts, max_attempts, merged) do
        nil -> merged
        policy -> Keyword.put(merged, :policy, policy)
      end
    end
  end

  defp normalize_retry_attempts(nil), do: nil

  defp normalize_retry_attempts(value) when is_integer(value) and value >= 0, do: value

  defp normalize_retry_attempts(_), do: nil

  defp build_http_retry_policy(
         %Context{retry: retry} = context,
         endpoint,
         request_opts,
         max_attempts,
         opts
       ) do
    if retry_supports_http_policy?(retry) do
      backoff = build_backoff(retry, opts)

      policy_opts =
        opts
        |> Keyword.put(:max_attempts, max_attempts)
        |> Keyword.put(:backoff, backoff)
        |> Keyword.put(:retry_on, &classified_retry?(context, endpoint, request_opts, &1))
        |> Keyword.put(
          :retry_after_ms_fun,
          &classified_retry_after_ms(context, endpoint, request_opts, &1)
        )

      retry.build_policy(policy_opts)
    else
      nil
    end
  end

  # Mox exports optional callbacks on generated mocks, but generic retry mocks do not
  # necessarily opt into the HTTP-aware policy-building path.
  defp retry_supports_http_policy?(retry) do
    is_atom(retry) and
      Code.ensure_loaded?(retry) and
      not function_exported?(retry, :__mock_for__, 0) and
      function_exported?(retry, :build_policy, 1) and
      function_exported?(retry, :build_backoff, 1)
  end

  defp build_backoff(retry, opts) do
    case normalize_backoff_source(opts) do
      {:ready, backoff} ->
        backoff

      backoff_opts ->
        retry.build_backoff(backoff_opts)
    end
  end

  defp normalize_backoff_source(opts) do
    backoff = Keyword.get(opts, :backoff)
    backoff_opts = normalize_backoff_opts(opts)

    case backoff do
      nil ->
        merge_default_backoff_opts(backoff_opts)

      source when is_list(source) or is_map(source) ->
        source
        |> normalize_backoff_opts()
        |> Keyword.merge(backoff_opts)
        |> merge_default_backoff_opts()

      source ->
        case normalize_backoff_strategy(source) do
          nil -> {:ready, source}
          strategy -> merge_default_backoff_opts(Keyword.put(backoff_opts, :strategy, strategy))
        end
    end
  end

  defp normalize_backoff_value(value) when is_list(value) or is_map(value),
    do: normalize_backoff_opts(value)

  defp normalize_backoff_value(value), do: normalize_backoff_strategy(value) || value

  defp normalize_backoff_opts(opts) when is_list(opts) or is_map(opts) do
    opts
    |> Enum.reduce([], fn {key, value}, acc ->
      case normalize_backoff_entry(key, value) do
        nil -> acc
        option -> [option | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp normalize_backoff_opts(_opts), do: []

  defp normalize_backoff_entry(key, value) do
    case normalize_backoff_key(key) do
      :legacy -> raise_legacy_retry_key!(key)
      nil -> nil
      :jitter_strategy -> {:jitter_strategy, normalize_backoff_jitter_strategy(value) || value}
      :strategy -> {:strategy, normalize_backoff_strategy(value) || value}
      atom_key -> {atom_key, value}
    end
  end

  defp normalize_backoff_key(key) when is_atom(key) do
    cond do
      key in @backoff_keys -> key
      key in @legacy_retry_keys -> :legacy
      true -> nil
    end
  end

  defp normalize_backoff_key(key) when is_binary(key) do
    cond do
      Map.has_key?(@backoff_string_keys, key) -> Map.fetch!(@backoff_string_keys, key)
      key in @legacy_retry_keys -> :legacy
      true -> nil
    end
  end

  defp normalize_backoff_key(_key), do: nil

  defp normalize_backoff_strategy(value) when is_atom(value) do
    if value in @backoff_strategies, do: value, else: nil
  end

  defp normalize_backoff_strategy(value) when is_binary(value),
    do: Map.get(@backoff_strategy_aliases, value)

  defp normalize_backoff_strategy(_value), do: nil

  defp normalize_backoff_jitter_strategy(value) when is_atom(value) do
    if value in @backoff_jitter_strategies, do: value, else: nil
  end

  defp normalize_backoff_jitter_strategy(value) when is_binary(value),
    do: Map.get(@backoff_jitter_strategy_aliases, value)

  defp normalize_backoff_jitter_strategy(_value), do: nil

  defp merge_default_backoff_opts(backoff_opts),
    do: Keyword.merge(default_backoff_opts(), backoff_opts)

  defp default_backoff_opts do
    [
      strategy: :exponential,
      base_ms: 500,
      max_ms: 10_000,
      jitter_strategy: :factor,
      jitter: 0.25
    ]
  end

  defp reject_legacy_retry_keys!(opts) do
    Enum.each(opts, fn {key, _value} ->
      if key in @legacy_retry_keys do
        raise_legacy_retry_key!(key)
      end
    end)
  end

  defp raise_legacy_retry_key!(key) do
    raise ArgumentError,
          "legacy retry option #{inspect(key)} is not supported; use :max_attempts, :base_ms, :max_ms, or :backoff"
  end

  defp raise_unknown_retry_key!(key) do
    raise ArgumentError,
          "unknown retry option #{inspect(key)}; supported keys are :backoff, :base_ms, :jitter, :jitter_strategy, :max_attempts, :max_ms, :progress_timeout_ms, :retry_after_ms_fun, :retry_on, :strategy"
  end

  defp rate_limit_opts(%{rate_limit: nil}, %Context{rate_limit_opts: opts}), do: opts

  defp rate_limit_opts(endpoint, %Context{rate_limit_opts: opts}) do
    Keyword.put_new(opts, :key, endpoint.rate_limit || endpoint.id)
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

  defp resolve_auth(_auth, nil, :error), do: []
  defp resolve_auth(_auth, [], :error), do: []

  defp resolve_auth(auth, security, :error) when is_list(security) do
    resolve_security_auth(auth, security)
  end

  defp resolve_auth(_auth, _security, {:ok, override}),
    do: normalize_auth_override!(override)

  defp resolve_auth(_auth, [], _override), do: []

  defp resolve_auth(auth, security, _override) when is_list(security) do
    resolve_security_auth(auth, security)
  end

  defp resolve_auth(_auth, nil, _override), do: []

  defp resolve_security_auth(auth, security) do
    case find_matching_security_modules(auth, security) do
      nil ->
        raise ArgumentError,
              "no configured auth satisfies security requirements: #{inspect(security)}"

      modules ->
        modules
    end
  end

  defp find_matching_security_modules(auth, security) do
    Enum.find_value(security, fn requirement ->
      case resolve_requirement_set(auth, requirement) do
        {:ok, modules} -> modules
        :error -> nil
      end
    end)
  end

  defp resolve_requirement_set(_auth, requirement)
       when is_map(requirement) and map_size(requirement) == 0,
       do: {:ok, []}

  defp resolve_requirement_set(auth, requirement) when is_map(requirement) do
    Enum.reduce_while(requirement, {:ok, []}, fn {scheme, _scopes}, {:ok, acc} ->
      case scheme_auth_modules(auth, scheme) do
        [] -> {:halt, :error}
        modules -> {:cont, {:ok, acc ++ modules}}
      end
    end)
  end

  defp resolve_requirement_set(_auth, _requirement), do: :error

  defp scheme_auth_modules(auth, _scheme) when is_list(auth), do: auth

  defp scheme_auth_modules(auth, scheme) when is_map(auth) do
    key = to_string(scheme)

    case Map.fetch(auth, key) do
      {:ok, modules} ->
        normalize_configured_auth_modules!(modules)

      :error ->
        auth
        |> Map.get("default", [])
        |> normalize_configured_auth_modules!()
    end
  end

  defp scheme_auth_modules(_auth, _scheme), do: []

  defp normalize_configured_auth_modules!(nil), do: []
  defp normalize_configured_auth_modules!(false), do: []

  defp normalize_configured_auth_modules!(modules) do
    normalize_auth_override!(modules)
  end

  defp normalize_auth_override!(nil), do: []
  defp normalize_auth_override!(false), do: []
  defp normalize_auth_override!([]), do: []

  defp normalize_auth_override!({module, opts})
       when is_atom(module) and is_list(opts) do
    [{module, opts}]
  end

  defp normalize_auth_override!(override) when is_list(override) do
    if Enum.all?(override, &match?({module, opts} when is_atom(module) and is_list(opts), &1)) do
      override
    else
      raise ArgumentError, "invalid auth override: #{inspect(override)}"
    end
  end

  defp normalize_auth_override!(override) when is_binary(override) do
    [Bearer.new(override)]
  end

  defp normalize_auth_override!(override) when is_map(override) do
    normalized =
      Map.new(override, fn {key, value} ->
        {to_string(key), value}
      end)

    cond do
      Map.has_key?(normalized, "client_id") and Map.has_key?(normalized, "client_secret") ->
        [
          Basic.new(
            normalized["client_id"],
            normalized["client_secret"]
          )
        ]

      Map.has_key?(normalized, "username") and Map.has_key?(normalized, "password") ->
        [
          Basic.new(
            normalized["username"],
            normalized["password"]
          )
        ]

      true ->
        raise ArgumentError, "invalid auth override: #{inspect(override)}"
    end
  end

  defp normalize_auth_override!(override) do
    raise ArgumentError, "invalid auth override: #{inspect(override)}"
  end

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

      cond do
        logger_configured?(context) and log_enabled?(context, :debug) ->
          maybe_log(context, :debug, "request attempt", %{
            attempt: attempt,
            endpoint_id: request.endpoint_id,
            method: method,
            url: url,
            headers: normalize_header_map(redacted),
            body: body_dump
          })

        logger_configured?(context) ->
          :ok

        true ->
          Logger.info(
            "HTTP #{method} #{url} attempt=#{attempt} headers=#{inspect(redacted)} body=#{body_dump}"
          )
      end
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
    pool_type = PoolRouting.resolve_type(endpoint, opts)
    path = Keyword.get(opts, :path, endpoint.path)

    base =
      %{
        endpoint_id: endpoint.id,
        method: HTTPMethod.telemetry(endpoint.method),
        path: path,
        pool_type: pool_type,
        base_url: context.base_url,
        resource: endpoint.resource,
        retry_group: endpoint.retry,
        breaker_name: circuit_breaker_name(endpoint)
      }
      |> Map.merge(context.telemetry_metadata || %{})

    case Keyword.get(opts, :telemetry_metadata) do
      meta when is_map(meta) -> Map.merge(base, meta)
      _ -> base
    end
  end

  defp maybe_log(%Context{} = context, level, message, metadata) when is_map(metadata) do
    if logger_configured?(context) and log_enabled?(context, level) do
      context.logger.(level, message, metadata)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp logger_configured?(%Context{logger: logger}), do: is_function(logger, 3)

  defp log_enabled?(%Context{log_level: threshold}, level) do
    log_level_severity(level) >= log_level_severity(normalize_log_level(threshold))
  end

  defp normalize_log_level(:warning), do: :warn
  defp normalize_log_level(:debug), do: :debug
  defp normalize_log_level(:info), do: :info
  defp normalize_log_level(:warn), do: :warn
  defp normalize_log_level(:error), do: :error
  defp normalize_log_level("warning"), do: :warn
  defp normalize_log_level("debug"), do: :debug
  defp normalize_log_level("info"), do: :info
  defp normalize_log_level("warn"), do: :warn
  defp normalize_log_level("error"), do: :error
  defp normalize_log_level(_), do: :info

  defp log_level_severity(:debug), do: 20
  defp log_level_severity(:info), do: 40
  defp log_level_severity(:warn), do: 60
  defp log_level_severity(:error), do: 80

  defp log_reason(reason) do
    cond do
      is_binary(reason) ->
        reason

      is_atom(reason) ->
        Atom.to_string(reason)

      is_struct(reason) and function_exported?(reason.__struct__, :message, 1) ->
        Exception.message(reason)

      true ->
        inspect(reason)
    end
  end

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

  defp maybe_apply_limiter_backoff(rate_limiter, result, endpoint, context, rl_opts, opts) do
    classification = attempt_classification(result, context, endpoint, opts)

    case classification.limiter_backoff_ms do
      duration_ms when is_integer(duration_ms) and duration_ms >= 0 ->
        maybe_set_limiter_backoff(rate_limiter, duration_ms, rl_opts)

      _ ->
        :ok
    end
  end

  defp maybe_set_limiter_backoff(rate_limiter, duration_ms, rl_opts) do
    if function_exported?(rate_limiter, :for_key, 2) and function_exported?(rate_limiter, :set, 3) do
      key = Keyword.get(rl_opts, :key, :default)
      limiter = rate_limiter.for_key(key, rl_opts)
      rate_limiter.set(limiter, duration_ms, rl_opts)
    else
      :ok
    end
  end

  defp maybe_apply_admission_backoff(
         admission_control,
         result,
         endpoint,
         context,
         admission_opts,
         opts
       ) do
    classification = attempt_classification(result, context, endpoint, opts)

    case classification.limiter_backoff_ms do
      duration_ms when is_integer(duration_ms) and duration_ms >= 0 ->
        if function_exported?(admission_control, :set_backoff, 2) do
          admission_control.set_backoff(duration_ms, admission_opts)
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp classified_retry?(context, endpoint, opts, result) do
    attempt_classification(result, context, endpoint, opts).retry?
  end

  defp classified_retry_after_ms(context, endpoint, opts, result) do
    attempt_classification(result, context, endpoint, opts).retry_after_ms
  end

  defp classify_result(%Context{} = context, result, endpoint, opts) do
    classifier = context.result_classifier || Pristine.Adapters.ResultClassifier.HTTP

    classifier
    |> invoke_classifier(result, endpoint, context, opts)
    |> ResultClassification.normalize()
  end

  defp invoke_classifier(classifier, result, endpoint, context, opts) when is_atom(classifier) do
    classifier.classify(result, endpoint, context, opts)
  end

  defp invoke_classifier(classifier, result, endpoint, context, opts)
       when is_function(classifier, 4) do
    classifier.(result, endpoint, context, opts)
  end

  defp invoke_classifier(classifier, result, endpoint, _context, opts)
       when is_function(classifier, 3) do
    classifier.(result, endpoint, opts)
  end

  defp invoke_classifier(classifier, result, endpoint, _context, _opts)
       when is_function(classifier, 2) do
    classifier.(result, endpoint)
  end

  defp invoke_classifier(_classifier, _result, _endpoint, _context, _opts), do: %{}

  defp attempt_outcome(result, %ResultClassification{} = classification) do
    {@attempt_outcome_tag, result, classification}
  end

  defp attempt_result({@attempt_outcome_tag, result, _classification}), do: result
  defp attempt_result(result), do: result

  defp attempt_classification(
         {@attempt_outcome_tag, _result, %ResultClassification{} = classification},
         _context,
         _endpoint,
         _opts
       ) do
    classification
  end

  defp attempt_classification(result, context, endpoint, opts) do
    classify_result(context, result, endpoint, opts)
  end

  defp admission_opts(%Request{} = request, endpoint, %Context{admission_opts: base_opts}) do
    base_opts
    |> Keyword.put_new(:estimated_bytes, request_bytes(request.body))
    |> Keyword.put_new(:resource, endpoint.resource)
    |> Keyword.put_new(:endpoint_id, endpoint.id)
  end

  defp request_bytes(nil), do: 0

  defp request_bytes(body) do
    body
    |> IO.iodata_length()
  rescue
    _ -> 0
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
          method: HTTPMethod.telemetry(response.metadata[:method] || response.metadata["method"]),
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
         response_ref,
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
        handle_success_response(response, serializer, response_ref, endpoint, context, opts)

      true ->
        handle_error_response(response, serializer, context, opts)
    end
  end

  defp decode_body(serializer, body, opts) do
    decoded = serializer.decode(body, nil, opts)
    normalize_decode_result(decoded)
  end

  defp handle_success_response(
         %Response{status: status, body: body},
         serializer,
         response_ref,
         endpoint,
         context,
         opts
       ) do
    response_ref = response_schema_for_status(response_ref, status)
    response_schema = RuntimeSchema.resolve_schema(response_ref, context.type_schemas)

    case decode_body(serializer, body, opts) do
      {:ok, decoded} ->
        decoded
        |> unwrap_response(endpoint)
        |> validate_success_payload(response_schema, response_ref, context, opts)

      {:error, _} when body in [nil, ""] ->
        validate_success_payload(%{}, response_schema, response_ref, context, opts)

      {:error, reason} ->
        success_validation_error(context, reason, body)
    end
  end

  defp validate_success_payload(payload, response_schema, response_ref, context, opts) do
    case validate_response_schema(payload, response_schema, opts) do
      {:ok, validated} ->
        {:ok, maybe_materialize_response(validated, response_ref, context, opts)}

      {:error, reason} ->
        success_validation_error(context, reason, payload)
    end
  end

  defp success_validation_error(context, reason, payload) do
    if error_module?(context) do
      {:error, validation_error(context, reason, payload)}
    else
      {:error, reason}
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

  defp validation_reason?(%Sinter.Error{}), do: true
  defp validation_reason?([%Sinter.Error{} | _]), do: true
  defp validation_reason?(_reason), do: false

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
    opts = Keyword.put(opts, :path, normalize_validation_path(Keyword.get(opts, :path, [])))
    Sinter.Validator.validate(schema, data, opts)
  end

  defp validate_response_schema(data, type_spec, opts) do
    path = normalize_validation_path(Keyword.get(opts, :path, []))
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

  defp normalize_validation_path(path) when is_list(path), do: path
  defp normalize_validation_path(_path), do: []

  defp maybe_materialize_response(data, response_ref, %Context{} = context, opts) do
    if Keyword.get(opts, :typed_responses, false) do
      RuntimeSchema.materialize(response_ref, data, context.type_schemas)
    else
      data
    end
  end

  defp response_schema_for_status(response_ref, status)

  defp response_schema_for_status(%{} = response_ref, status) when is_integer(status) do
    Map.get(response_ref, status) ||
      Map.get(response_ref, Integer.to_string(status)) ||
      Map.get(response_ref, :default) ||
      Map.get(response_ref, "default")
  end

  defp response_schema_for_status(response_ref, _status), do: response_ref
end
