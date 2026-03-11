defmodule Pristine.OpenAPI.Runtime do
  @moduledoc """
  Runtime helpers for OpenAPI-generated schema modules and direct schema refs.
  """

  alias Sinter.Schema

  @non_module_ref_heads [
    nil,
    true,
    false,
    :array,
    :boolean,
    :const,
    :enum,
    :integer,
    :literal,
    :map,
    :nullable,
    :number,
    :object,
    :string,
    :tuple,
    :union
  ]

  @type openapi_field :: %{
          required(:default) => term(),
          required(:name) => String.t(),
          required(:nullable) => boolean(),
          required(:required) => boolean(),
          required(:type) => term()
        }

  @spec build_schema([openapi_field()]) :: Schema.t()
  def build_schema(fields) when is_list(fields) do
    field_specs =
      Enum.map(fields, fn field ->
        type =
          field.type
          |> to_runtime_type()
          |> maybe_nullable(field.nullable)

        {
          field.name,
          type,
          field_opts(field)
        }
      end)

    Schema.define(field_specs)
  end

  @spec decode_module_type(module(), atom(), term()) :: {:ok, term()} | {:error, term()}
  def decode_module_type(module, type, data) when is_atom(module) and is_atom(type) do
    with {:ok, validated} <- Sinter.Validator.validate(module.__schema__(type), data) do
      {:ok, materialize_module(module, type, validated)}
    end
  end

  @spec resolve_schema(term(), map()) :: term() | nil
  def resolve_schema(nil, _type_schemas), do: nil
  def resolve_schema(%Schema{} = schema, _type_schemas), do: schema

  def resolve_schema(ref, type_schemas) when is_binary(ref) do
    case Map.get(type_schemas || %{}, ref) do
      nil -> nil
      schema -> resolve_type_spec(schema, type_schemas, true)
    end
  end

  def resolve_schema(ref, type_schemas) when is_atom(ref) do
    case Map.get(type_schemas || %{}, Atom.to_string(ref)) do
      nil -> resolve_type_spec(ref, type_schemas, true)
      schema -> resolve_type_spec(schema, type_schemas, true)
    end
  end

  def resolve_schema(ref, type_schemas) do
    resolve_type_spec(ref, type_schemas, true)
  end

  @spec materialize(term(), term(), map()) :: term()
  def materialize(nil, data, _type_schemas), do: data

  def materialize(ref, data, type_schemas) when is_binary(ref) do
    case Map.get(type_schemas || %{}, ref) do
      nil -> data
      schema -> materialize_spec(schema, data, type_schemas)
    end
  end

  def materialize(ref, data, type_schemas) when is_atom(ref) do
    case Map.get(type_schemas || %{}, Atom.to_string(ref)) do
      nil -> materialize_spec(ref, data, type_schemas)
      schema -> materialize_spec(schema, data, type_schemas)
    end
  end

  def materialize(ref, data, type_schemas) do
    materialize_spec(ref, data, type_schemas)
  end

  defp field_opts(field) do
    []
    |> maybe_put_required(field.required)
    |> maybe_put_default(field.default)
  end

  defp maybe_put_required(opts, true), do: Keyword.put(opts, :required, true)
  defp maybe_put_required(opts, _required), do: Keyword.put(opts, :optional, true)

  defp maybe_put_default(opts, nil), do: opts
  defp maybe_put_default(opts, default), do: Keyword.put(opts, :default, default)

  defp maybe_nullable(type, true), do: {:union, [type, :null]}
  defp maybe_nullable(type, false), do: type

  defp materialize_module(module, type, validated) do
    fields =
      if function_exported?(module, :__openapi_fields__, 1) do
        module.__openapi_fields__(type)
      else
        []
      end

    values =
      Enum.reduce(fields, %{}, fn field, acc ->
        case Map.fetch(validated, field.name) do
          {:ok, value} ->
            Map.put(
              acc,
              String.to_atom(field.name),
              materialize_openapi_value(field.type, value)
            )

          :error ->
            acc
        end
      end)

    if function_exported?(module, :__struct__, 0) do
      struct(module, values)
    else
      values
    end
  end

  defp materialize_spec({module, type}, data, _type_schemas)
       when is_atom(module) and is_atom(type) do
    case invoke_module_decode(module, type, data) do
      {:ok, materialized} -> materialized
      {:error, _reason} -> data
    end
  end

  defp materialize_spec({:union, types}, data, type_schemas) do
    choose_union_candidate(types, data, fn type ->
      materialize_spec(type, data, type_schemas)
    end)
  end

  defp materialize_spec([inner], data, type_schemas) when is_list(data) do
    Enum.map(data, &materialize_spec(inner, &1, type_schemas))
  end

  defp materialize_spec(_ref, data, _type_schemas), do: data

  defp materialize_openapi_value(_type, nil), do: nil

  defp materialize_openapi_value({module, type}, value)
       when is_map(value) and is_atom(module) and is_atom(type) do
    case invoke_module_decode(module, type, value) do
      {:ok, materialized} -> materialized
      {:error, _reason} -> value
    end
  end

  defp materialize_openapi_value([inner], value) when is_list(value) do
    Enum.map(value, &materialize_openapi_value(inner, &1))
  end

  defp materialize_openapi_value({:union, types}, value) do
    choose_union_candidate(types, value, &materialize_openapi_value(&1, value))
  end

  defp materialize_openapi_value({:string, "date"}, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> value
    end
  end

  defp materialize_openapi_value({:string, "date-time"}, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, datetime} -> datetime
          _ -> value
        end
    end
  end

  defp materialize_openapi_value({:string, "time"}, value) when is_binary(value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> time
      _ -> value
    end
  end

  defp materialize_openapi_value(_type, value), do: value

  defp union_candidate_changed?({module, type}, value) when is_atom(module) and is_atom(type) do
    case invoke_module_decode(module, type, value) do
      {:ok, materialized} -> materialized != value
      {:error, _} -> false
    end
  end

  defp union_candidate_changed?({:string, format}, value)
       when format in ["date", "date-time", "time"] and is_binary(value) do
    materialize_openapi_value({:string, format}, value) != value
  end

  defp union_candidate_changed?([inner], value) when is_list(value) do
    Enum.any?(value, &(materialize_openapi_value(inner, &1) != &1))
  end

  defp union_candidate_changed?(_type, _value), do: false

  defp choose_union_candidate(types, value, materialize_fun) do
    types
    |> Enum.reduce([], fn type, candidates ->
      case union_match_score(type, value) do
        nil ->
          candidates

        score ->
          [{score, materialize_fun.(type)} | candidates]
      end
    end)
    |> case do
      [] ->
        value

      candidates ->
        candidates
        |> Enum.max_by(fn {score, _candidate} -> score end)
        |> elem(1)
    end
  end

  defp union_match_score({module, type}, value)
       when is_map(value) and is_atom(module) and is_atom(type) do
    case invoke_module_decode(module, type, value) do
      {:ok, _materialized} -> schema_field_count(module, type)
      {:error, _reason} -> nil
    end
  end

  defp union_match_score({:union, types}, value) do
    types
    |> Enum.map(&union_match_score(&1, value))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      scores -> Enum.max(scores)
    end
  end

  defp union_match_score([inner], value) when is_list(value) do
    1 + Enum.reduce(value, 0, fn item, total -> total + (union_match_score(inner, item) || 0) end)
  end

  defp union_match_score({:string, format}, value)
       when format in ["date", "date-time", "time"] and is_binary(value) do
    if union_candidate_changed?({:string, format}, value), do: 1, else: nil
  end

  defp union_match_score(type, value) do
    if union_candidate_changed?(type, value), do: 1, else: nil
  end

  defp schema_field_count(module, type) do
    cond do
      function_exported?(module, :__openapi_fields__, 1) ->
        module.__openapi_fields__(type) |> length()

      function_exported?(module, :__fields__, 1) ->
        module.__fields__(type) |> length()

      true ->
        0
    end
  end

  defp specificity_score({:object, %Schema{fields: fields}}), do: map_size(fields)
  defp specificity_score(%Schema{fields: fields}), do: map_size(fields)
  defp specificity_score({:array, inner}), do: specificity_score(inner)
  defp specificity_score([inner]), do: specificity_score(inner)

  defp specificity_score({:union, types}) do
    Enum.max(Enum.map(types, &specificity_score/1), fn -> 0 end)
  end

  defp specificity_score(_type), do: 0

  defp resolve_type_spec({module, type}, _type_schemas, top_level?)
       when is_atom(module) and is_atom(type) and module not in @non_module_ref_heads do
    ensure_module_loaded!(module)

    resolved =
      cond do
        function_exported?(module, :__schema__, 1) ->
          module.__schema__(type)

        function_exported?(module, :schema, 0) and type == :t ->
          module.schema()

        true ->
          raise ArgumentError,
                "cannot resolve OpenAPI runtime schema ref #{inspect({module, type})}: expected #{inspect(module)} to export __schema__/1 or schema/0"
      end

    wrap_resolved_schema(resolved, top_level?)
  end

  defp resolve_type_spec({:union, types}, type_schemas, top_level?) do
    types =
      types
      |> Enum.map(&resolve_type_spec(&1, type_schemas, false))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&specificity_score/1, :desc)

    case types do
      [] -> nil
      [single] when top_level? -> single
      [single] -> single
      many -> {:union, many}
    end
  end

  defp resolve_type_spec([inner], type_schemas, _top_level?) do
    case resolve_type_spec(inner, type_schemas, false) do
      nil -> nil
      resolved -> {:array, resolved}
    end
  end

  defp resolve_type_spec({:array, inner}, type_schemas, _top_level?) do
    case resolve_type_spec(inner, type_schemas, false) do
      nil -> nil
      resolved -> {:array, resolved}
    end
  end

  defp resolve_type_spec({:nullable, inner}, type_schemas, _top_level?) do
    case resolve_type_spec(inner, type_schemas, false) do
      nil -> nil
      resolved -> {:nullable, resolved}
    end
  end

  defp resolve_type_spec({:map, key_type, value_type}, type_schemas, _top_level?) do
    {:map, resolve_type_spec(key_type, type_schemas, false),
     resolve_type_spec(value_type, type_schemas, false)}
  end

  defp resolve_type_spec({:tuple, types}, type_schemas, _top_level?) do
    {:tuple, Enum.map(types, &resolve_type_spec(&1, type_schemas, false))}
  end

  defp resolve_type_spec({:object, %Schema{} = schema}, _type_schemas, top_level?) do
    wrap_resolved_schema(schema, top_level?)
  end

  defp resolve_type_spec(%Schema{} = schema, _type_schemas, top_level?) do
    wrap_resolved_schema(schema, top_level?)
  end

  defp resolve_type_spec(other, _type_schemas, _top_level?), do: other

  defp wrap_resolved_schema(nil, _top_level?), do: nil
  defp wrap_resolved_schema(%Schema{} = schema, true), do: schema
  defp wrap_resolved_schema(%Schema{} = schema, false), do: {:object, schema}
  defp wrap_resolved_schema(other, _top_level?), do: other

  defp to_runtime_type({module, type_name})
       when is_atom(module) and is_atom(type_name) and module not in @non_module_ref_heads do
    {module, type_name}
    |> resolve_type_spec(%{}, true)
    |> wrap_resolved_schema(false)
  end

  defp to_runtime_type([inner]), do: {:array, to_runtime_type(inner)}
  defp to_runtime_type({:array, inner}), do: {:array, to_runtime_type(inner)}
  defp to_runtime_type({:union, types}), do: {:union, Enum.map(types, &to_runtime_type/1)}
  defp to_runtime_type({:nullable, inner}), do: {:nullable, to_runtime_type(inner)}
  defp to_runtime_type({:tuple, types}), do: {:tuple, Enum.map(types, &to_runtime_type/1)}

  defp to_runtime_type({:map, key_type, value_type}) do
    {:map, to_runtime_type(key_type), to_runtime_type(value_type)}
  end

  defp to_runtime_type({:enum, literals}) when is_list(literals) do
    {:union, Enum.map(literals, &{:literal, &1})}
  end

  defp to_runtime_type({:const, literal}), do: {:literal, literal}
  defp to_runtime_type({:string, "date"}), do: :date
  defp to_runtime_type({:string, "date-time"}), do: :datetime
  defp to_runtime_type({:string, "time"}), do: :string
  defp to_runtime_type({:string, "uuid"}), do: :uuid
  defp to_runtime_type({:string, _format}), do: :string
  defp to_runtime_type({:integer, _format}), do: :integer
  defp to_runtime_type({:number, _format}), do: {:union, [:integer, :float]}
  defp to_runtime_type({:boolean, _format}), do: :boolean
  defp to_runtime_type(:number), do: {:union, [:integer, :float]}
  defp to_runtime_type(:unknown), do: :any
  defp to_runtime_type(other), do: other

  defp invoke_module_decode(module, type, data) do
    ensure_module_loaded!(module)

    cond do
      function_exported?(module, :decode, 2) ->
        module.decode(data, type)

      function_exported?(module, :decode, 1) and type == :t ->
        module.decode(data)

      true ->
        if function_exported?(module, :__schema__, 1) or
             (function_exported?(module, :schema, 0) and type == :t) do
          decode_module_type(module, type, data)
        else
          raise ArgumentError,
                "cannot decode OpenAPI runtime ref #{inspect({module, type})}: expected #{inspect(module)} to export decode/2, decode/1, __schema__/1, or schema/0"
        end
    end
  end

  defp ensure_module_loaded!(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _loaded} ->
        :ok

      {:error, _reason} ->
        raise ArgumentError,
              "cannot resolve OpenAPI runtime schema ref: module #{inspect(module)} is not available"
    end
  end
end
