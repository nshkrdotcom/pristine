defmodule Tinkex.Types.Cursor do
  @moduledoc """
  Cursor for paginated API responses.

  Contains offset, limit, and total count for pagination.
  """

  @enforce_keys [:offset, :limit, :total_count]
  defstruct [:offset, :limit, :total_count]

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          limit: non_neg_integer(),
          total_count: non_neg_integer()
        }

  @doc """
  Parse a Cursor from a map with string or atom keys.

  Returns nil if input is nil.
  """
  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(%{} = map) do
    %__MODULE__{
      offset: get_integer(map, "offset", :offset),
      limit: get_integer(map, "limit", :limit),
      total_count: get_integer(map, "total_count", :total_count)
    }
  end

  defp get_integer(map, string_key, atom_key) do
    value = Map.get(map, string_key) || Map.get(map, atom_key) || 0
    to_integer(value)
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
  defp to_integer(_), do: 0
end
