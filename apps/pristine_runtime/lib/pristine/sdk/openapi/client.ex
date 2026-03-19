defmodule Pristine.SDK.OpenAPI.Client do
  @moduledoc """
  SDK-facing OpenAPI request contracts for generated provider SDKs.
  """

  alias Pristine.OpenAPI.Client, as: RuntimeClient

  @type response_type :: RuntimeClient.response_type()
  @type request_t :: RuntimeClient.request_t()
  @type request_spec_t :: RuntimeClient.request_spec_t()

  @spec request(request_t()) :: {:ok, request_t()}
  defdelegate request(request), to: RuntimeClient

  @spec to_request_spec(request_t()) :: request_spec_t()
  defdelegate to_request_spec(request), to: RuntimeClient

  @doc false
  @spec request_schema(request_t()) :: term() | nil
  defdelegate request_schema(request), to: RuntimeClient

  @doc false
  @spec response_schema(request_t()) :: term() | nil
  defdelegate response_schema(request), to: RuntimeClient

  @doc false
  @spec request_id(request_t()) :: String.t() | nil
  defdelegate request_id(request), to: RuntimeClient
end
