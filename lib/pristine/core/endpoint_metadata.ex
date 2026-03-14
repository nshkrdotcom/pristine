defmodule Pristine.Core.EndpointMetadata do
  @moduledoc """
  Internal endpoint metadata contract used by the request pipeline.

  This struct carries the normalized request metadata that survives the
  streamlined public runtime boundary.
  """

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
          telemetry: String.t() | nil,
          timeout: non_neg_integer() | nil,
          request: term(),
          response: term(),
          response_unwrap: String.t() | nil,
          transform: keyword() | map() | nil,
          idempotency: boolean() | nil,
          idempotency_header: String.t() | nil
        }

  @spec from_request_spec(map(), keyword()) :: t()
  def from_request_spec(request_spec, opts \\ []) when is_map(request_spec) and is_list(opts) do
    %__MODULE__{
      id: Map.get(request_spec, :id),
      method: Map.get(request_spec, :method),
      path: Map.get(request_spec, :path),
      circuit_breaker: Map.get(request_spec, :circuit_breaker),
      headers: Map.get(request_spec, :headers, %{}),
      query: Map.get(request_spec, :query, %{}),
      rate_limit: Map.get(request_spec, :rate_limit),
      resource: Map.get(request_spec, :resource),
      body_type: Keyword.get(opts, :body_type),
      content_type: Keyword.get(opts, :content_type),
      retry: Map.get(request_spec, :retry),
      security: Map.get(request_spec, :security),
      telemetry: Map.get(request_spec, :telemetry),
      timeout: Map.get(request_spec, :timeout),
      request: Map.get(request_spec, :request_schema),
      response: Map.get(request_spec, :response_schema),
      response_unwrap: Map.get(request_spec, :response_unwrap),
      transform: Map.get(request_spec, :transform),
      idempotency: Map.get(request_spec, :idempotency),
      idempotency_header: Map.get(request_spec, :idempotency_header)
    }
  end
end
