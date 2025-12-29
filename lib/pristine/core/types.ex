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
    types = normalize_types(types)

    {compiled, _cache} =
      Enum.reduce(types, {%{}, %{}}, fn {name, defn}, {acc, cache} ->
        {spec, cache} = resolve_type_spec(name, defn, types, cache, [])
        {Map.put(acc, normalize_key(name), spec), cache}
      end)

    compiled
  end

  def compile(_), do: %{}

  defp resolve_type_spec(name, defn, types, cache, stack) do
    key = normalize_key(name)

    case cache do
      %{^key => spec} ->
        {spec, cache}

      _ ->
        if key in stack do
          {:map, cache}
        else
          stack = [key | stack]
          defn = defn || Map.get(types, key)
          {spec, cache} = build_type_spec(defn, types, cache, stack)
          {spec, Map.put(cache, key, spec)}
        end
    end
  end

  defp build_type_spec(defn, types, cache, stack) do
    case type_kind(defn) do
      :union -> build_union_spec(defn, types, cache, stack)
      :alias -> build_alias_spec(defn, types, cache, stack)
      :object -> build_object_schema(defn, types, cache, stack)
    end
  end

  defp build_object_schema(defn, types, cache, stack) do
    fields = fetch(defn, :fields) || %{}

    {field_specs, cache} =
      Enum.reduce(fields, {[], cache}, fn {name, field_def}, {acc, cache} ->
        {type_spec, cache} = resolve_field_type(field_def, types, cache, stack)
        opts = field_opts(field_def)
        {[{normalize_key(name), type_spec, opts} | acc], cache}
      end)

    {Schema.define(Enum.reverse(field_specs)), cache}
  end

  defp build_union_spec(defn, types, cache, stack) do
    discriminator = normalize_union_discriminator(defn)

    {variants, cache} =
      Enum.reduce(discriminator.mapping, {%{}, cache}, fn {disc_value, type_name}, {acc, cache} ->
        {spec, cache} =
          resolve_type_spec(
            type_name,
            Map.get(types, normalize_key(type_name)),
            types,
            cache,
            stack
          )

        schema = ensure_schema(spec)
        {Map.put(acc, disc_value, schema), cache}
      end)

    union_spec = {:discriminated_union, discriminator: discriminator.field, variants: variants}
    {union_spec, cache}
  end

  defp build_alias_spec(defn, types, cache, stack) do
    type_ref = fetch(defn, :type_ref)
    type = fetch(defn, :type)
    value = fetch(defn, :value)
    choices = fetch(defn, :choices)
    items = fetch(defn, :items)

    cond do
      not is_nil(type_ref) ->
        resolve_type_spec(type_ref, Map.get(types, normalize_key(type_ref)), types, cache, stack)

      is_list(choices) ->
        spec = {:union, Enum.map(choices, &{:literal, &1})}
        {spec, cache}

      not is_nil(value) ->
        {{:literal, value}, cache}

      normalize_key(type) == "array" ->
        {item_spec, cache} = resolve_item_type(items, types, cache, stack)
        {{:array, item_spec}, cache}

      not is_nil(type) ->
        {map_type(type), cache}

      true ->
        {:map, cache}
    end
  end

  defp resolve_field_type(field_def, types, cache, stack) do
    field_def = normalize_field_def(field_def)
    type_ref = fetch(field_def, :type_ref)
    type = fetch(field_def, :type) || "string"
    items = fetch(field_def, :items)
    value = fetch(field_def, :value)

    cond do
      not is_nil(type_ref) ->
        resolve_ref_spec(type_ref, types, cache, stack)

      normalize_key(type) == "array" ->
        {item_spec, cache} = resolve_item_type(items, types, cache, stack)
        {{:array, item_spec}, cache}

      normalize_key(type) == "literal" ->
        {{:literal, value}, cache}

      true ->
        {map_type(type), cache}
    end
  end

  defp resolve_item_type(nil, _types, cache, _stack), do: {:any, cache}

  defp resolve_item_type(item_def, types, cache, stack) do
    resolve_field_type(item_def, types, cache, stack)
  end

  defp resolve_ref_spec(type_ref, types, cache, stack) do
    {spec, cache} =
      resolve_type_spec(type_ref, Map.get(types, normalize_key(type_ref)), types, cache, stack)

    case spec do
      %Schema{} -> {{:object, spec}, cache}
      other -> {other, cache}
    end
  end

  defp ensure_schema(%Schema{} = schema), do: schema
  defp ensure_schema(_), do: Schema.define([])

  defp normalize_union_discriminator(defn) do
    disc = fetch(defn, :discriminator)
    variants = normalize_union_variants(defn) || %{}

    cond do
      is_map(disc) ->
        build_discriminator(disc, variants)

      is_binary(disc) or is_atom(disc) ->
        build_discriminator(normalize_key(disc), variants)

      true ->
        build_discriminator("type", variants)
    end
  end

  defp build_discriminator(disc, variants) when is_map(disc) do
    field = fetch(disc, :field) || "type"
    mapping = fetch(disc, :mapping) || variants
    build_discriminator(normalize_key(field), mapping)
  end

  defp build_discriminator(field, mapping) do
    %{field: field, mapping: normalize_variant_mapping(mapping)}
  end

  defp normalize_union_variants(defn) do
    case fetch(defn, :variants) do
      nil -> nil
      variants when is_map(variants) -> variants
      variants when is_list(variants) -> normalize_variant_list(variants)
      _ -> nil
    end
  end

  defp normalize_variant_list(variants) do
    Enum.reduce(variants, %{}, fn variant, acc ->
      variant_value =
        fetch(variant, :discriminator_value) || fetch(variant, :value) || fetch(variant, :tag)

      type_ref = fetch(variant, :type_ref) || fetch(variant, :type)

      if variant_value && type_ref do
        Map.put(acc, to_string(variant_value), normalize_key(type_ref))
      else
        acc
      end
    end)
  end

  defp normalize_variant_mapping(mapping) when is_map(mapping) do
    Enum.reduce(mapping, %{}, fn {k, v}, acc ->
      Map.put(acc, normalize_key(k), normalize_key(v))
    end)
  end

  defp normalize_variant_mapping(_), do: %{}

  defp type_kind(defn) when is_map(defn) do
    kind = fetch(defn, :kind) || fetch(defn, :type)

    cond do
      kind in [:union, "union"] -> :union
      kind in [:alias, "alias"] -> :alias
      kind in [:object, "object"] -> :object
      not is_nil(fetch(defn, :fields)) -> :object
      alias_definition?(defn) -> :alias
      true -> :object
    end
  end

  defp type_kind(_), do: :object

  defp alias_definition?(defn) do
    type = fetch(defn, :type)
    type_ref = fetch(defn, :type_ref)
    value = fetch(defn, :value)
    choices = fetch(defn, :choices)

    not is_nil(type) or not is_nil(type_ref) or not is_nil(value) or not is_nil(choices)
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

  defp map_type(type) do
    Map.get(@type_mapping, normalize_key(type), :any)
  end

  defp normalize_types(types) do
    Map.new(types, fn {name, defn} -> {normalize_key(name), defn} end)
  end

  defp normalize_field_def(defn) when is_map(defn), do: defn
  defp normalize_field_def(defn), do: %{type: defn}

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp fetch(defn, key) when is_map(defn) do
    Map.get(defn, key) || Map.get(defn, to_string(key))
  end

  defp fetch(_defn, _key), do: nil
end
