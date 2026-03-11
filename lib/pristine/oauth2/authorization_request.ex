defmodule Pristine.OAuth2.AuthorizationRequest do
  @moduledoc """
  Authorization URL and any generated state associated with it.
  """

  defstruct url: nil,
            state: nil,
            pkce_verifier: nil,
            pkce_challenge: nil,
            pkce_method: nil

  @type t :: %__MODULE__{
          url: String.t() | nil,
          state: String.t() | nil,
          pkce_verifier: String.t() | nil,
          pkce_challenge: String.t() | nil,
          pkce_method: :plain | :s256 | nil
        }
end
