defmodule Pristine.OAuth2.Token do
  @moduledoc """
  Pristine-native OAuth2 token representation.
  """

  defstruct access_token: nil,
            refresh_token: nil,
            expires_at: nil,
            token_type: "Bearer",
            other_params: %{}

  @type t :: %__MODULE__{
          access_token: String.t() | nil,
          refresh_token: String.t() | nil,
          expires_at: integer() | nil,
          token_type: String.t(),
          other_params: map()
        }

  @spec from_backend_token(map()) :: t()
  def from_backend_token(token) when is_map(token) do
    %__MODULE__{
      access_token: Map.get(token, :access_token),
      refresh_token: Map.get(token, :refresh_token),
      expires_at: Map.get(token, :expires_at),
      token_type: Map.get(token, :token_type, "Bearer"),
      other_params: Map.get(token, :other_params, %{})
    }
  end

  @spec expires?(t()) :: boolean()
  def expires?(%__MODULE__{expires_at: nil}), do: false
  def expires?(%__MODULE__{}), do: true

  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{} = token) do
    expires?(token) and System.system_time(:second) > token.expires_at
  end
end
