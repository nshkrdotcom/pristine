defmodule PristineCodegen.JSON do
  @moduledoc false

  alias Jason.OrderedObject

  @spec encode!(term()) :: String.t()
  def encode!(term) do
    term
    |> ordered_json_term()
    |> Jason.encode_to_iodata!(pretty: true)
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  defp ordered_json_term(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> ordered_json_term()
  end

  defp ordered_json_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), ordered_json_term(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> OrderedObject.new()
  end

  defp ordered_json_term(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&ordered_json_term/1)
  end

  defp ordered_json_term(list) when is_list(list), do: Enum.map(list, &ordered_json_term/1)
  defp ordered_json_term(value), do: value
end
