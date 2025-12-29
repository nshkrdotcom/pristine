defmodule Pristine.Core.Querystring do
  @moduledoc """
  Query string encoder with configurable array and nested formats.
  """

  @type array_format :: :comma | :repeat | :indices | :brackets
  @type nested_format :: :dots | :brackets

  @spec stringify(map() | keyword(), keyword()) :: String.t()
  def stringify(params, opts \\ []) do
    params
    |> encode(opts)
    |> URI.encode_query()
  end

  @spec encode(map() | keyword(), keyword()) :: [{String.t(), String.t()}]
  def encode(params, opts \\ []) do
    array_format = normalize_array_format(Keyword.get(opts, :array_format, :repeat))
    nested_format = normalize_nested_format(Keyword.get(opts, :nested_format, :brackets))

    params
    |> normalize_params()
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.flat_map(fn {key, value} ->
      encode_value(to_string(key), value, array_format, nested_format)
    end)
    |> Enum.with_index()
    |> Enum.sort_by(fn {{key, _value}, index} -> {key, index} end)
    |> Enum.map(fn {pair, _index} -> pair end)
  end

  defp encode_value(_key, nil, _array_format, _nested_format), do: []

  defp encode_value(key, value, array_format, nested_format) when is_map(value) do
    value
    |> Map.to_list()
    |> Enum.sort_by(fn {subkey, _subvalue} -> to_string(subkey) end)
    |> Enum.flat_map(fn {subkey, subvalue} ->
      encode_value(
        join_key(key, to_string(subkey), nested_format),
        subvalue,
        array_format,
        nested_format
      )
    end)
  end

  defp encode_value(key, value, array_format, nested_format) when is_list(value) do
    list = Enum.reject(value, &is_nil/1)

    case list do
      [] -> []
      _ -> encode_list(key, list, array_format, nested_format)
    end
  end

  defp encode_value(key, value, _array_format, _nested_format) do
    [{key, normalize_value(value)}]
  end

  defp encode_list(key, list, :comma, nested_format) do
    if Enum.all?(list, &primitive?/1) do
      values = Enum.map(list, &normalize_value/1)
      [{key, Enum.join(values, ",")}]
    else
      encode_list(key, list, :repeat, nested_format)
    end
  end

  defp encode_list(key, list, array_format, nested_format) do
    Enum.with_index(list)
    |> Enum.flat_map(fn {item, index} ->
      item_key = list_key(key, index, array_format)
      encode_value(item_key, item, array_format, nested_format)
    end)
  end

  defp join_key(prefix, key, :dots), do: prefix <> "." <> key
  defp join_key(prefix, key, :brackets), do: prefix <> "[" <> key <> "]"

  defp list_key(key, _index, :repeat), do: key
  defp list_key(key, _index, :brackets), do: key <> "[]"
  defp list_key(key, index, :indices), do: key <> "[" <> Integer.to_string(index) <> "]"

  defp normalize_params(params) when is_map(params), do: Map.to_list(params)

  defp normalize_params(params) when is_list(params) do
    if Enum.all?(params, &match?({_, _}, &1)) do
      params
    else
      []
    end
  end

  defp normalize_params(_params), do: []

  defp normalize_value(true), do: "true"
  defp normalize_value(false), do: "false"
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value), do: to_string(value)

  defp primitive?(value) when is_map(value), do: false
  defp primitive?(value) when is_list(value), do: false
  defp primitive?(_value), do: true

  defp normalize_array_format(value) when is_binary(value) do
    value |> String.downcase() |> normalize_array_format()
  end

  defp normalize_array_format(value) when is_atom(value) do
    case value do
      :comma -> :comma
      :repeat -> :repeat
      :indices -> :indices
      :brackets -> :brackets
      _ -> :repeat
    end
  end

  defp normalize_array_format(_value), do: :repeat

  defp normalize_nested_format(value) when is_binary(value) do
    value |> String.downcase() |> normalize_nested_format()
  end

  defp normalize_nested_format(value) when is_atom(value) do
    case value do
      :dots -> :dots
      :brackets -> :brackets
      _ -> :brackets
    end
  end

  defp normalize_nested_format(_value), do: :brackets
end
