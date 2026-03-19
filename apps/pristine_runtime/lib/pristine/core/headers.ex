defmodule Pristine.Core.Headers do
  @moduledoc """
  Header normalization and merging utilities.
  """

  alias Pristine.Core.Auth

  @spec build(map(), map(), list(), map(), binary() | nil) :: {:ok, map()} | {:error, term()}
  def build(base_headers, endpoint_headers, auth_modules, extra_headers, content_type) do
    merged =
      base_headers
      |> normalize_headers()
      |> Map.merge(normalize_headers(endpoint_headers))
      |> Map.merge(normalize_headers(extra_headers))

    with {:ok, headers} <- Auth.apply(auth_modules, merged) do
      {:ok, maybe_put_content_type(headers, content_type)}
    end
  end

  defp normalize_headers(headers) when is_map(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_key(key), to_string(value))
    end)
  end

  defp normalize_headers(_), do: %{}

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp maybe_put_content_type(headers, nil), do: headers

  defp maybe_put_content_type(headers, content_type) do
    Map.put_new(headers, "content-type", content_type)
  end
end
