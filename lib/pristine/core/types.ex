defmodule Pristine.Core.Types do
  @moduledoc """
  Build Sinter schemas from manifest type definitions.
  """

  alias Sinter.Schema

  # Type mapping for reducing cyclomatic complexity
  @type_mapping %{
    "string" => :string,
    "integer" => :integer,
    "float" => :float,
    "number" => :float,
    "boolean" => :boolean,
    "map" => :map,
    "object" => :map
  }

  @spec compile(map()) :: map()
  def compile(types) when is_map(types) do
    Enum.reduce(types, %{}, fn {name, definition}, acc ->
      Map.put(acc, normalize_key(name), build_schema(definition))
    end)
  end

  def compile(_), do: %{}

  defp build_schema(%{fields: fields}) when is_map(fields) do
    Schema.define(Enum.map(fields, &field_spec/1))
  end

  defp build_schema(_), do: Schema.define([])

  defp field_spec({name, defn}) do
    type = resolve_type(defn)
    opts = field_opts(defn)
    {normalize_key(name), type, opts}
  end

  defp resolve_type(defn) when is_map(defn) do
    type = Map.get(defn, :type) || Map.get(defn, "type") || "string"
    type_key = normalize_key(type)

    if type_key == "array" do
      {:array, resolve_array_item(defn)}
    else
      Map.get(@type_mapping, type_key, :any)
    end
  end

  defp resolve_type(_), do: :string

  defp resolve_array_item(defn) do
    item = Map.get(defn, :items) || Map.get(defn, "items") || "string"
    Map.get(@type_mapping, normalize_key(item), :any)
  end

  defp field_opts(defn) do
    required = fetch(defn, :required)
    optional = fetch(defn, :optional)

    []
    |> maybe_add_opt(:required, required)
    |> maybe_add_opt(:optional, optional)
    |> maybe_add_opt(:default, fetch(defn, :default))
    |> maybe_add_opt(:description, fetch(defn, :description))
    |> maybe_add_opt(:min_length, fetch(defn, :min_length))
    |> maybe_add_opt(:max_length, fetch(defn, :max_length))
    |> maybe_add_opt(:min_items, fetch(defn, :min_items))
    |> maybe_add_opt(:max_items, fetch(defn, :max_items))
    |> maybe_add_opt(:gt, fetch(defn, :gt))
    |> maybe_add_opt(:gteq, fetch(defn, :gteq))
    |> maybe_add_opt(:lt, fetch(defn, :lt))
    |> maybe_add_opt(:lteq, fetch(defn, :lteq))
    |> maybe_add_opt(:format, fetch(defn, :format))
    |> maybe_add_opt(:choices, fetch(defn, :choices))
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, false), do: opts
  defp maybe_add_opt(opts, key, true), do: Keyword.put(opts, key, true)
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp fetch(defn, key), do: Map.get(defn, key) || Map.get(defn, to_string(key))
end
