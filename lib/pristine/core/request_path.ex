defmodule Pristine.Core.RequestPath do
  @moduledoc """
  Request path validation helpers.
  """

  @spec validate!(String.t()) :: :ok
  def validate!(path) when is_binary(path) do
    if traversal_path?(path) do
      raise ArgumentError, path_traversal_message(path)
    end

    :ok
  end

  @spec validate!(term()) :: :ok
  def validate!(path) do
    path
    |> to_string()
    |> validate!()
  end

  @spec validate_path_params!(map()) :: :ok
  def validate_path_params!(params) when is_map(params) do
    Enum.each(params, fn {key, value} ->
      if traversal_path?(to_string(value)) do
        raise ArgumentError, path_param_traversal_message(key, value)
      end
    end)

    :ok
  end

  def validate_path_params!(_params), do: :ok

  defp traversal_path?(value) when is_binary(value) do
    String.contains?(value, "..") or encoded_traversal?(value)
  end

  defp encoded_traversal?(value) do
    if String.match?(value, ~r/%2e/i) do
      decoded_contains_traversal?(value)
    else
      false
    end
  end

  defp decoded_contains_traversal?(value) do
    value
    |> URI.decode()
    |> String.contains?("..")
  rescue
    ArgumentError -> false
  end

  defp path_traversal_message(path) do
    "request path contains path traversal sequence: #{inspect(path)}"
  end

  defp path_param_traversal_message(key, value) do
    "path parameter #{inspect(key)} contains path traversal sequence: #{inspect(value)}"
  end
end
