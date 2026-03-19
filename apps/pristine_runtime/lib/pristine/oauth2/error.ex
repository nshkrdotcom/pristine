defmodule Pristine.OAuth2.Error do
  @moduledoc """
  Error returned by the Pristine OAuth2 control-plane helpers.
  """

  defexception [:reason, :message, :status, :body, :headers, :provider]

  @type t :: %__MODULE__{
          reason: atom(),
          message: String.t(),
          status: integer() | nil,
          body: term(),
          headers: map(),
          provider: term()
        }

  @spec new(atom(), keyword()) :: t()
  def new(reason, opts \\ []) do
    %__MODULE__{
      reason: reason,
      message: Keyword.get(opts, :message, default_message(reason)),
      status: Keyword.get(opts, :status),
      body: Keyword.get(opts, :body),
      headers: Keyword.get(opts, :headers, %{}),
      provider: Keyword.get(opts, :provider)
    }
  end

  defp default_message(:authorization_request_requires_explicit_values),
    do: "authorize_url/2 requires explicit state or PKCE inputs"

  defp default_message(:authorization_callback_error),
    do: "authorization callback returned an error"

  defp default_message(:authorization_callback_timeout),
    do: "timed out waiting for the authorization callback"

  defp default_message(:authorization_code_missing),
    do: "authorization response did not include a code"

  defp default_message(:authorization_state_mismatch),
    do: "authorization response state did not match request state"

  defp default_message(:invalid_context), do: "a Pristine context with transport is required"
  defp default_message(:invalid_redirect_uri), do: "redirect_uri must be a valid absolute URI"
  defp default_message(:manual_input_cancelled), do: "authorization input was cancelled"
  defp default_message(:missing_client_id), do: "client_id is required"
  defp default_message(:missing_redirect_uri), do: "redirect_uri is required"
  defp default_message(:missing_client_secret), do: "client_secret is required"
  defp default_message(:missing_token_url), do: "provider token_url is required"
  defp default_message(:missing_authorize_url), do: "provider authorize_url is required"
  defp default_message(:missing_revocation_url), do: "provider revocation_url is required"
  defp default_message(:missing_introspection_url), do: "provider introspection_url is required"
  defp default_message(:oauth2_unavailable), do: "oauth2 dependency is not available"

  defp default_message(:redirect_uri_mismatch),
    do: "authorization response URI did not match redirect_uri"

  defp default_message(:unsupported_callback_scheme),
    do: "loopback callback capture requires an http redirect_uri"

  defp default_message(:loopback_callback_unavailable),
    do: "loopback callback capture requires a literal loopback IP redirect_uri"

  defp default_message(:token_request_failed), do: "token request failed"
  defp default_message(reason), do: "oauth2 error: #{reason}"
end
