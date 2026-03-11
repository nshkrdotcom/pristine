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

  @standard_backend_keys [
    :__struct__,
    :access_token,
    :refresh_token,
    :expires_at,
    :expires_in,
    :expires,
    :token_type,
    :other_params,
    "__struct__",
    "access_token",
    "refresh_token",
    "expires_at",
    "expires_in",
    "expires",
    "token_type",
    "other_params"
  ]

  @spec from_backend_token(map()) :: t()
  def from_backend_token(token) when is_map(token) do
    %__MODULE__{
      access_token: fetch_value(token, :access_token),
      refresh_token: fetch_value(token, :refresh_token),
      expires_at: normalize_backend_expires_at(token),
      token_type: normalize_token_type(fetch_value(token, :token_type)),
      other_params: backend_other_params(token)
    }
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

  defp backend_other_params(token) do
    token
    |> Map.drop(@standard_backend_keys)
    |> stringify_top_level_keys()
    |> Map.merge(normalize_other_params(fetch_value(token, :other_params)))
  end

  defp normalize_backend_expires_at(token) do
    case fetch_value(token, :expires_at) do
      value when is_integer(value) -> value
      value when is_binary(value) -> parse_integer(value)
      _other -> normalize_backend_expiry_offset(token)
    end
  end

  defp normalize_backend_expiry_offset(token) do
    case fetch_value(token, :expires_in) || fetch_value(token, :expires) do
      value when is_integer(value) and value >= 0 ->
        System.system_time(:second) + value

      value when is_binary(value) ->
        case parse_integer(value) do
          integer when is_integer(integer) and integer >= 0 ->
            System.system_time(:second) + integer

          _other ->
            nil
        end

      _other ->
        nil
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp stringify_top_level_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_other_params(%{} = other_params), do: other_params
  defp normalize_other_params(_other), do: %{}

  defp normalize_token_type(token_type) when is_binary(token_type) do
    case String.trim(token_type) do
      "" ->
        "Bearer"

      type ->
        if String.downcase(type) == "bearer" do
          "Bearer"
        else
          type
        end
    end
  end

  defp normalize_token_type(_token_type), do: "Bearer"
end
