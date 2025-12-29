defmodule Pristine.Core.Url do
  @moduledoc """
  URL builder with path params and query encoding.
  """

  alias Pristine.Core.Querystring

  @spec build(String.t() | nil, String.t(), map(), map(), keyword()) :: String.t()
  def build(base_url, path, path_params, query_params, opts \\ []) do
    base = normalize_base(base_url)
    path = normalize_path(path)
    path = apply_path_params(path, path_params)

    url = base <> path

    query_string = Querystring.stringify(query_params, opts)

    if query_string == "" do
      url
    else
      url <> "?" <> query_string
    end
  end

  defp normalize_base(nil), do: ""
  defp normalize_base(base) when is_binary(base), do: String.trim_trailing(base, "/")

  defp normalize_path(path) do
    path = to_string(path)

    if String.starts_with?(path, "/") do
      path
    else
      "/" <> path
    end
  end

  defp apply_path_params(path, params) when is_map(params) do
    Enum.reduce(params, path, fn {key, value}, acc ->
      value = URI.encode(to_string(value))

      acc
      |> String.replace("{" <> normalize_key(key) <> "}", value)
      |> String.replace(":" <> normalize_key(key), value)
    end)
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)
end
