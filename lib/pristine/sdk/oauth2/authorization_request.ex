defmodule Pristine.SDK.OAuth2.AuthorizationRequest do
  @moduledoc """
  SDK-facing OAuth2 authorization request contract.
  """

  alias Pristine.OAuth2.AuthorizationRequest, as: RuntimeAuthorizationRequest

  @type t :: RuntimeAuthorizationRequest.t()
end
