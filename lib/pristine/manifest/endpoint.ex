defmodule Pristine.Manifest.Endpoint do
  @moduledoc """
  Endpoint definition extracted from a manifest.
  """

  defstruct id: nil,
            method: nil,
            path: nil,
            description: nil,
            request: nil,
            response: nil,
            retry: nil,
            telemetry: nil,
            streaming: false,
            headers: %{},
            query: %{},
            body_type: nil,
            content_type: nil,
            auth: nil,
            circuit_breaker: nil,
            rate_limit: nil,
            idempotency: false

  @type t :: %__MODULE__{
          id: String.t(),
          method: String.t(),
          path: String.t(),
          description: String.t() | nil,
          request: String.t() | nil,
          response: String.t() | nil,
          retry: String.t() | nil,
          telemetry: String.t() | nil,
          streaming: boolean(),
          headers: map(),
          query: map(),
          body_type: String.t() | nil,
          content_type: String.t() | nil,
          auth: String.t() | nil,
          circuit_breaker: String.t() | nil,
          rate_limit: String.t() | nil,
          idempotency: boolean()
        }
end
