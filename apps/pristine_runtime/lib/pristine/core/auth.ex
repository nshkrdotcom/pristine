defmodule Pristine.Core.Auth do
  @moduledoc """
  Apply auth modules to request headers.
  """

  @spec apply(list(), map()) :: {:ok, map()} | {:error, term()}
  def apply(auth_modules, headers) when is_list(auth_modules) do
    Enum.reduce_while(auth_modules, {:ok, headers}, fn {module, opts}, {:ok, acc} ->
      case module.headers(opts) do
        {:ok, new_headers} -> {:cont, {:ok, Map.merge(acc, new_headers)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def apply(_, headers), do: {:ok, headers}
end
