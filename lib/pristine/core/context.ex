defmodule Pristine.Core.Context do
  @moduledoc """
  Runtime context for executing manifest-driven requests.
  """

  defstruct base_url: nil,
            headers: %{},
            auth: [],
            transport: nil,
            transport_opts: [],
            stream_transport: nil,
            serializer: nil,
            multipart: nil,
            multipart_opts: [],
            retry: nil,
            retry_opts: [],
            rate_limiter: nil,
            rate_limit_opts: [],
            circuit_breaker: nil,
            circuit_breaker_opts: [],
            telemetry: nil,
            future: nil,
            future_opts: [],
            retry_policies: %{},
            type_schemas: %{},
            idempotency_header: "X-Idempotency-Key"

  @type t :: %__MODULE__{
          base_url: String.t() | nil,
          headers: map(),
          auth: list(),
          transport: module() | nil,
          transport_opts: keyword(),
          stream_transport: module() | nil,
          serializer: module() | nil,
          multipart: module() | nil,
          multipart_opts: keyword(),
          retry: module() | nil,
          retry_opts: keyword(),
          rate_limiter: module() | nil,
          rate_limit_opts: keyword(),
          circuit_breaker: module() | nil,
          circuit_breaker_opts: keyword(),
          telemetry: module() | nil,
          future: module() | nil,
          future_opts: keyword(),
          retry_policies: map(),
          type_schemas: map(),
          idempotency_header: String.t()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      base_url: Keyword.get(opts, :base_url),
      headers: Keyword.get(opts, :headers, %{}),
      auth: Keyword.get(opts, :auth, []),
      transport: Keyword.get(opts, :transport),
      transport_opts: Keyword.get(opts, :transport_opts, []),
      stream_transport: Keyword.get(opts, :stream_transport),
      serializer: Keyword.get(opts, :serializer),
      multipart: Keyword.get(opts, :multipart),
      multipart_opts: Keyword.get(opts, :multipart_opts, []),
      retry: Keyword.get(opts, :retry),
      retry_opts: Keyword.get(opts, :retry_opts, []),
      rate_limiter: Keyword.get(opts, :rate_limiter),
      rate_limit_opts: Keyword.get(opts, :rate_limit_opts, []),
      circuit_breaker: Keyword.get(opts, :circuit_breaker),
      circuit_breaker_opts: Keyword.get(opts, :circuit_breaker_opts, []),
      telemetry: Keyword.get(opts, :telemetry),
      future: Keyword.get(opts, :future),
      future_opts: Keyword.get(opts, :future_opts, []),
      retry_policies: Keyword.get(opts, :retry_policies, %{}),
      type_schemas: Keyword.get(opts, :type_schemas, %{}),
      idempotency_header: Keyword.get(opts, :idempotency_header, "X-Idempotency-Key")
    }
  end
end
