defmodule Pristine.Core.EndpointMetadata do
  @moduledoc """
  Internal endpoint metadata contract used by the request pipeline.

  This struct carries the normalized request metadata that survives the
  streamlined public runtime boundary.
  """

  alias Pristine.Operation

  defstruct id: nil,
            method: nil,
            path: nil,
            circuit_breaker: nil,
            headers: %{},
            query: %{},
            rate_limit: nil,
            resource: nil,
            body_type: nil,
            content_type: nil,
            retry: nil,
            security: nil,
            telemetry: nil,
            timeout: nil,
            request: nil,
            response: nil,
            response_unwrap: nil,
            transform: nil,
            idempotency: nil,
            idempotency_header: nil

  @type t :: %__MODULE__{
          id: String.t() | atom() | nil,
          method: String.t() | atom() | nil,
          path: String.t() | nil,
          circuit_breaker: String.t() | nil,
          headers: map(),
          query: map(),
          rate_limit: String.t() | nil,
          resource: String.t() | nil,
          body_type: String.t() | atom() | nil,
          content_type: String.t() | nil,
          retry: String.t() | nil,
          security: [map()] | nil,
          telemetry: term(),
          timeout: non_neg_integer() | nil,
          request: term(),
          response: term(),
          response_unwrap: String.t() | nil,
          transform: keyword() | map() | nil,
          idempotency: boolean() | nil,
          idempotency_header: String.t() | nil
        }

  @spec from_operation(Operation.t(), keyword()) :: t()
  def from_operation(%Operation{} = operation, opts \\ []) when is_list(opts) do
    %__MODULE__{
      id: operation.id,
      method: operation.method,
      path: operation.path_template,
      circuit_breaker: operation.runtime.circuit_breaker,
      headers: operation.headers || %{},
      query: operation.query || %{},
      rate_limit: operation.runtime.rate_limit_group,
      resource: operation.runtime.resource,
      body_type: Keyword.get(opts, :body_type),
      content_type: Keyword.get(opts, :content_type),
      retry: operation.runtime.retry_group,
      security: security_requirements(operation.auth.security_schemes),
      telemetry: operation.runtime.telemetry_event,
      timeout: operation.runtime.timeout_ms,
      request: operation.request_schema,
      response: operation.response_schemas
    }
  end

  @spec from_request_spec(map(), keyword()) :: t()
  def from_request_spec(request_spec, opts \\ []) when is_map(request_spec) and is_list(opts) do
    headers =
      Map.get(request_spec, :headers, %{})
      |> normalize_string_key_map()

    %__MODULE__{
      id: Map.get(request_spec, :id),
      method: Map.get(request_spec, :method),
      path: Map.get(request_spec, :path),
      circuit_breaker: Map.get(request_spec, :circuit_breaker),
      headers: headers,
      query: normalize_string_key_map(Map.get(request_spec, :query, %{})),
      rate_limit: Map.get(request_spec, :rate_limit),
      resource: Map.get(request_spec, :resource),
      body_type: Keyword.get(opts, :body_type),
      content_type: Keyword.get(opts, :content_type),
      retry: Map.get(request_spec, :retry),
      security: normalize_security_requirements(request_spec),
      telemetry: Map.get(request_spec, :telemetry),
      timeout: Map.get(request_spec, :timeout),
      request: Map.get(request_spec, :request_schema),
      response: response_schema_map(Map.get(request_spec, :response_schema)),
      response_unwrap: Map.get(request_spec, :response_unwrap),
      transform: Map.get(request_spec, :transform),
      idempotency: Map.get(request_spec, :idempotency),
      idempotency_header: Map.get(request_spec, :idempotency_header)
    }
  end

  defp security_requirements([]), do: nil

  defp security_requirements(schemes) when is_list(schemes) do
    Enum.map(schemes, &%{to_string(&1) => []})
  end

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

  defp normalize_security_requirements(%{security: security}) when is_list(security), do: security

  defp normalize_security_requirements(%{auth: %{security_schemes: schemes}})
       when is_list(schemes) do
    security_requirements(schemes)
  end

  defp normalize_security_requirements(_request_spec), do: nil

  defp response_schema_map(nil), do: %{}
  defp response_schema_map(%{} = response_schema), do: response_schema
  defp response_schema_map(response_schema), do: %{default: response_schema}
end
