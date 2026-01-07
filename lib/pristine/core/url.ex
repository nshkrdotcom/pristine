defmodule Pristine.Core.Url do
  @moduledoc """
  URL builder with path params and query encoding.
  """

  alias Pristine.Core.Querystring

  @spec build(String.t() | nil, String.t(), map(), map(), keyword()) :: String.t()
  def build(base_url, path, path_params, query_params, opts \\ []) do
    base = normalize_base(base_url)
    {path, embedded_query} = split_query(path)
    path = normalize_path(path)
    path = apply_path_params(path, path_params)

    url = base <> path

    merged_query =
      embedded_query
      |> Map.merge(normalize_query_params(query_params))

    query_string = Querystring.stringify(merged_query, opts)

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

  defp split_query(path) do
    path = to_string(path)

    case String.split(path, "?", parts: 2) do
      [base] -> {base, %{}}
      [base, query] -> {base, decode_query(query)}
    end
  end

  defp decode_query(""), do: %{}

  defp decode_query(query) do
    URI.decode_query(query)
  rescue
    _ -> %{}
  end

  defp normalize_query_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp normalize_query_params(params) when is_list(params) do
    if Enum.all?(params, &match?({_, _}, &1)) do
      params
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Map.new()
    else
      %{}
    end
  end

  defp normalize_query_params(_), do: %{}
end
