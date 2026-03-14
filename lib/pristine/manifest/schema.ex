defmodule Pristine.Manifest.Schema do
  @moduledoc """
  NimbleOptions schema for top-level manifest validation.
  """

  alias NimbleOptions

  @map_key_type {:or, [:atom, :string]}
  @any_map {:map, @map_key_type, :any}
  @map_list {:list, @any_map}
  @schema NimbleOptions.new!(
            name: [type: :string, required: true],
            version: [type: :string, required: true],
            base_url: [type: :string],
            security_schemes: [type: @any_map],
            security: [type: @map_list],
            error_types: [type: @any_map],
            endpoints: [type: @map_list, required: true],
            types: [type: @any_map, required: true],
            retry_policies: [type: @any_map],
            rate_limits: [type: @any_map],
            resources: [type: @any_map],
            servers: [type: @any_map],
            middleware: [type: @any_map],
            defaults: [type: @any_map]
          )
  @allowed_keys @schema.schema |> Keyword.keys() |> Map.new(&{&1, true})
  @string_keys @schema.schema
               |> Enum.map(fn {key, _opts} -> {Atom.to_string(key), key} end)
               |> Map.new()

  @spec schema() :: NimbleOptions.t()
  def schema do
    @schema
  end

  @spec validate(map()) :: {:ok, map()} | {:error, Exception.t()}
  def validate(input) when is_map(input) do
    input
    |> top_level_options()
    |> NimbleOptions.validate(@schema)
    |> case do
      {:ok, validated} -> {:ok, Map.new(validated)}
      {:error, error} -> {:error, error}
    end
  end

  def validate(_input) do
    {:error, %ArgumentError{message: "manifest must be a map"}}
  end

  defp top_level_options(input) do
    Enum.reduce(input, [], fn {key, value}, acc ->
      normalized_key = normalize_key(key)

      if Map.has_key?(@allowed_keys, normalized_key) do
        [{normalized_key, value} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key), do: Map.get(@string_keys, key, key)

  defp normalize_key(key), do: key
end
