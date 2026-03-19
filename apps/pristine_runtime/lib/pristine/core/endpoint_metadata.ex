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

  defp security_requirements([]), do: nil

  defp security_requirements(schemes) when is_list(schemes) do
    Enum.map(schemes, &%{to_string(&1) => []})
  end
end
