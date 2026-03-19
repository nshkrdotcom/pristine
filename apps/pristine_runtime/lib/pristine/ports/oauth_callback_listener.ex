defmodule Pristine.Ports.OAuthCallbackListener do
  @moduledoc """
  Boundary for loopback OAuth callback capture.
  """

  alias Pristine.OAuth2.Error

  @callback start(String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  @callback await(term(), timeout()) ::
              {:ok, %{code: String.t(), request_uri: String.t(), state: String.t() | nil}}
              | {:error, Error.t()}
  @callback stop(term()) :: :ok
  @callback loopback_redirect_uri?(String.t()) :: boolean()
end
