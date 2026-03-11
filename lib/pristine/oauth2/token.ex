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
    from_map(token)
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = token) do
    %{
      "access_token" => token.access_token,
      "refresh_token" => token.refresh_token,
      "expires_at" => token.expires_at,
      "token_type" => token.token_type,
      "other_params" => normalize_other_params(token.other_params)
    }
  end

  @spec from_map(map()) :: t()
  def from_map(token) when is_map(token) do
    %__MODULE__{
      access_token: fetch_value(token, :access_token),
      refresh_token: fetch_value(token, :refresh_token),
      expires_at: fetch_value(token, :expires_at),
      token_type: normalize_token_type(fetch_value(token, :token_type)),
      other_params: normalize_other_params(fetch_value(token, :other_params))
    }
  end

  @spec expires?(t()) :: boolean()
  def expires?(%__MODULE__{expires_at: nil}), do: false
  def expires?(%__MODULE__{}), do: true

  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{} = token) do
    expires?(token) and System.system_time(:second) > token.expires_at
  end

  defp fetch_value(map, key) when is_map(map) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end

  defp normalize_other_params(%{} = other_params), do: other_params
  defp normalize_other_params(_other), do: %{}

  defp normalize_token_type(token_type) when is_binary(token_type) and token_type != "",
    do: token_type

  defp normalize_token_type(_token_type), do: "Bearer"
end
