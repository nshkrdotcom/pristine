defmodule Pristine.Manifest do
  @moduledoc """
  Manifest normalization and validation.
  """

  alias Pristine.Manifest.{Endpoint, Loader, Schema}
  alias Sinter.{Error, Validator}

  defstruct name: nil,
            version: nil,
            endpoints: %{},
            types: %{},
            policies: %{}

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          endpoints: %{String.t() => Endpoint.t()},
          types: map(),
          policies: map()
        }

  @spec load(map()) :: {:ok, t()} | {:error, [String.t()]}
  def load(input) when is_map(input) do
    schema = Schema.schema()

    case Validator.validate(schema, input, coerce: true) do
      {:ok, validated} ->
        build_manifest(validated)

      {:error, errors} ->
        {:error, Enum.map(errors, &format_error/1)}
    end
  end

  def load(_input) do
    {:error, ["manifest must be a map"]}
  end

  defp build_manifest(validated) do
    name = normalize_value(validated, :name)
    version = normalize_value(validated, :version)
    endpoints = normalize_value(validated, :endpoints)
    types = normalize_value(validated, :types)
    policies = normalize_value(validated, :policies) || %{}

    errors =
      []
      |> maybe_require(name, "name is required")
      |> maybe_require(version, "version is required")
      |> maybe_require(endpoints, "endpoints are required")
      |> maybe_require(types, "types are required")

    {endpoint_map, endpoint_errors} = normalize_endpoints(endpoints)
    {type_map, type_errors} = normalize_types(types)

    errors = errors ++ endpoint_errors ++ type_errors

    if errors == [] do
      {:ok,
       %__MODULE__{
         name: name,
         version: version,
         endpoints: endpoint_map,
         types: type_map,
         policies: policies || %{}
       }}
    else
      {:error, errors}
    end
  end

  @spec load_file(Path.t()) :: {:ok, t()} | {:error, [String.t()]}
  def load_file(path) do
    case Loader.load_file(path) do
      {:ok, manifest} -> load(manifest)
      {:error, _} = error -> error
    end
  end

  @spec fetch_endpoint!(t(), String.t() | atom()) :: Endpoint.t()
  def fetch_endpoint!(%__MODULE__{endpoints: endpoints}, endpoint_id) do
    key = normalize_key(endpoint_id)

    case Map.fetch(endpoints, key) do
      {:ok, endpoint} -> endpoint
      :error -> raise KeyError, "unknown endpoint: #{key}"
    end
  end

  defp normalize_endpoints(nil), do: {%{}, []}

  defp normalize_endpoints(endpoints) when is_list(endpoints) do
    Enum.reduce(endpoints, {%{}, []}, fn endpoint, {acc, errors} ->
      case normalize_endpoint(endpoint) do
        {:ok, %Endpoint{} = normalized} ->
          {Map.put(acc, normalized.id, normalized), errors}

        {:error, error} ->
          {acc, errors ++ [error]}
      end
    end)
  end

  defp normalize_endpoints(_), do: {%{}, ["endpoints must be a list"]}

  defp normalize_endpoint(endpoint) when is_map(endpoint) do
    id = normalize_value(endpoint, :id)
    method = normalize_value(endpoint, :method)
    path = normalize_value(endpoint, :path)

    cond do
      is_nil(id) ->
        {:error, "endpoint id is required"}

      is_nil(method) or is_nil(path) ->
        {:error, "endpoint #{normalize_key(id)} must include method and path"}

      not String.starts_with?(to_string(path), "/") ->
        {:error, "endpoint #{normalize_key(id)} path must start with '/'"}

      true ->
        {:ok,
         %Endpoint{
           id: normalize_key(id),
           method: normalize_method(method),
           path: to_string(path),
           request: normalize_optional(endpoint, :request),
           response: normalize_optional(endpoint, :response),
           retry: normalize_optional(endpoint, :retry),
           telemetry: normalize_optional(endpoint, :telemetry),
           streaming: normalize_boolean(endpoint, :streaming, false),
           headers: normalize_map(endpoint, :headers),
           query: normalize_map(endpoint, :query),
           body_type: normalize_optional(endpoint, :body_type),
           content_type: normalize_value(endpoint, :content_type),
           auth: normalize_optional(endpoint, :auth),
           circuit_breaker: normalize_optional(endpoint, :circuit_breaker),
           rate_limit: normalize_optional(endpoint, :rate_limit)
         }}
    end
  end

  defp normalize_endpoint(_), do: {:error, "endpoint entry must be a map"}

  defp normalize_types(nil), do: {%{}, []}

  defp normalize_types(types) when is_map(types) do
    Enum.reduce(types, {%{}, []}, fn {name, definition}, {acc, errors} ->
      case normalize_type(name, definition) do
        {:ok, {type_name, normalized}} -> {Map.put(acc, type_name, normalized), errors}
        {:error, error} -> {acc, errors ++ [error]}
      end
    end)
  end

  defp normalize_types(_), do: {%{}, ["types must be a map"]}

  defp normalize_type(name, definition) when is_map(definition) do
    type_name = normalize_key(name)
    fields = normalize_value(definition, :fields)

    if is_map(fields) do
      {:ok, {type_name, %{fields: normalize_field_defs(fields)}}}
    else
      {:error, "type #{type_name} must include fields"}
    end
  end

  defp normalize_type(name, _definition) do
    {:error, "type #{normalize_key(name)} must be a map"}
  end

  defp normalize_field_defs(fields) do
    Enum.reduce(fields, %{}, fn {field, definition}, acc ->
      Map.put(acc, normalize_key(field), normalize_field(definition))
    end)
  end

  defp normalize_field(definition) when is_map(definition) do
    %{
      type: normalize_optional(definition, :type),
      required: normalize_boolean(definition, :required, false),
      optional: normalize_boolean(definition, :optional, false),
      default: normalize_value(definition, :default),
      description: normalize_value(definition, :description),
      alias: normalize_optional(definition, :alias),
      omit_if: normalize_optional(definition, :omit_if),
      min_length: normalize_value(definition, :min_length),
      max_length: normalize_value(definition, :max_length),
      min_items: normalize_value(definition, :min_items),
      max_items: normalize_value(definition, :max_items),
      gt: normalize_value(definition, :gt),
      gteq: normalize_value(definition, :gteq),
      lt: normalize_value(definition, :lt),
      lteq: normalize_value(definition, :lteq),
      format: normalize_value(definition, :format),
      choices: normalize_value(definition, :choices)
    }
  end

  defp normalize_field(definition) do
    %{type: definition, required: false, optional: false}
  end

  defp normalize_method(method) when is_atom(method),
    do: method |> Atom.to_string() |> String.upcase()

  defp normalize_method(method) when is_binary(method), do: String.upcase(method)
  defp normalize_method(method), do: to_string(method) |> String.upcase()

  defp normalize_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_optional(map, key) when is_map(map) do
    case normalize_value(map, key) do
      nil -> nil
      value -> normalize_key(value)
    end
  end

  defp normalize_boolean(map, key, default) when is_map(map) do
    case normalize_value(map, key) do
      nil -> default
      value -> value == true
    end
  end

  defp normalize_map(map, key) when is_map(map) do
    case normalize_value(map, key) do
      nil ->
        %{}

      value when is_map(value) ->
        Enum.reduce(value, %{}, fn {k, v}, acc ->
          Map.put(acc, normalize_key(k), v)
        end)

      _ ->
        %{}
    end
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp format_error(%Error{} = error) do
    path = error.path |> List.wrap() |> Enum.map_join(".", &to_string/1)

    if path == "" do
      error.message
    else
      "#{path} #{error.message}"
    end
  end

  defp format_error(error), do: to_string(error)

  defp maybe_require(errors, nil, message), do: errors ++ [message]
  defp maybe_require(errors, _value, _message), do: errors
end
