defmodule Pristine.Manifest do
  @moduledoc """
  Manifest normalization and validation.
  """

  alias Pristine.Manifest.{Endpoint, Loader, Schema}
  alias Sinter.{Error, Validator}

  defstruct name: nil,
            version: nil,
            base_url: nil,
            auth: nil,
            defaults: %{},
            error_types: %{},
            resources: %{},
            servers: %{},
            retry_policies: %{},
            rate_limits: %{},
            middleware: %{},
            endpoints: %{},
            types: %{},
            policies: %{}

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          base_url: String.t() | nil,
          auth: map() | nil,
          defaults: map(),
          error_types: map(),
          resources: map(),
          servers: map(),
          retry_policies: map(),
          rate_limits: map(),
          middleware: map(),
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
    fields = normalize_manifest_fields(validated)
    errors = required_field_errors(fields)

    {endpoint_map, endpoint_errors} = normalize_endpoints(fields.endpoints)
    {type_map, type_errors} = normalize_types(fields.types)

    errors = errors ++ endpoint_errors ++ type_errors

    if errors == [] do
      {:ok,
       %__MODULE__{
         name: fields.name,
         version: fields.version,
         base_url: fields.base_url,
         auth: fields.auth,
         defaults: fields.defaults,
         error_types: fields.error_types,
         resources: fields.resources,
         servers: fields.servers,
         retry_policies: fields.retry_policies,
         rate_limits: fields.rate_limits,
         middleware: fields.middleware,
         endpoints: endpoint_map,
         types: type_map,
         policies: fields.policies
       }}
    else
      {:error, errors}
    end
  end

  defp normalize_manifest_fields(validated) do
    %{
      name: normalize_value(validated, :name),
      version: normalize_value(validated, :version),
      base_url: normalize_value(validated, :base_url),
      auth: normalize_deep_map(validated, :auth),
      defaults: normalize_optional_map(validated, :defaults),
      error_types: normalize_optional_map(validated, :error_types),
      resources: normalize_optional_map(validated, :resources),
      servers: normalize_optional_map(validated, :servers),
      retry_policies: normalize_retry_policies(validated),
      rate_limits: normalize_optional_map(validated, :rate_limits),
      middleware: normalize_optional_map(validated, :middleware),
      endpoints: normalize_value(validated, :endpoints),
      types: normalize_value(validated, :types),
      policies: normalize_policies(validated)
    }
  end

  defp normalize_optional_map(validated, key) do
    normalize_deep_map(validated, key) || %{}
  end

  defp normalize_retry_policies(validated) do
    normalize_deep_map(validated, :retry_policies) ||
      normalize_deep_map(validated, :policies) ||
      %{}
  end

  defp normalize_policies(validated) do
    normalize_value(validated, :policies) || %{}
  end

  defp required_field_errors(fields) do
    []
    |> maybe_require(fields.name, "name is required")
    |> maybe_require(fields.version, "version is required")
    |> maybe_require(fields.endpoints, "endpoints are required")
    |> maybe_require(fields.types, "types are required")
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
           description: normalize_value(endpoint, :description),
           resource: normalize_optional(endpoint, :resource),
           request: normalize_optional(endpoint, :request),
           response: normalize_optional(endpoint, :response),
           async: normalize_boolean(endpoint, :async, false),
           poll_endpoint: normalize_optional(endpoint, :poll_endpoint),
           timeout: normalize_value(endpoint, :timeout),
           retry: normalize_optional(endpoint, :retry),
           telemetry: normalize_optional(endpoint, :telemetry),
           streaming: normalize_boolean(endpoint, :streaming, false),
           stream_format: normalize_value(endpoint, :stream_format),
           event_types: normalize_string_list(endpoint, :event_types),
           headers: normalize_map(endpoint, :headers),
           query: normalize_map(endpoint, :query),
           body_type: normalize_optional(endpoint, :body_type),
           content_type: normalize_value(endpoint, :content_type),
           auth: normalize_optional(endpoint, :auth),
           circuit_breaker: normalize_optional(endpoint, :circuit_breaker),
           rate_limit: normalize_optional(endpoint, :rate_limit),
           idempotency: normalize_boolean(endpoint, :idempotency, false),
           idempotency_header: normalize_value(endpoint, :idempotency_header),
           deprecated: normalize_boolean(endpoint, :deprecated, false),
           tags: normalize_string_list(endpoint, :tags),
           error_types: normalize_list(endpoint, :error_types),
           response_unwrap: normalize_value(endpoint, :response_unwrap),
           transform: normalize_transform(endpoint)
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
    kind = normalize_type_kind(definition)
    description = normalize_value(definition, :description)
    fields = normalize_value(definition, :fields)

    cond do
      kind == :union ->
        {:ok, {type_name, normalize_union_type(definition, description)}}

      is_map(fields) ->
        {:ok,
         {type_name,
          %{kind: :object, description: description, fields: normalize_field_defs(fields)}}}

      has_alias_type?(definition) ->
        {:ok,
         {type_name,
          %{
            kind: :alias,
            description: description,
            type: normalize_value(definition, :type),
            type_ref: normalize_type_ref(definition),
            value: normalize_value(definition, :value),
            choices: normalize_value(definition, :choices)
          }}}

      true ->
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
      type_ref: normalize_type_ref(definition),
      items: normalize_items(definition),
      value: normalize_value(definition, :value),
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

  defp normalize_transform(map) when is_map(map) do
    case normalize_value(map, :transform) do
      nil -> nil
      value -> value
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

  defp normalize_deep_map(map, key) when is_map(map) do
    case normalize_value(map, key) do
      nil -> nil
      value when is_map(value) -> deep_normalize_map(value)
      _ -> nil
    end
  end

  defp deep_normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {k, v}, acc ->
      Map.put(acc, normalize_key(k), deep_normalize_map(v))
    end)
  end

  defp deep_normalize_map(value) when is_list(value) do
    Enum.map(value, &deep_normalize_map/1)
  end

  defp deep_normalize_map(value), do: value

  defp normalize_string_list(map, key) when is_map(map) do
    case normalize_value(map, key) do
      nil -> nil
      list when is_list(list) -> Enum.map(list, &to_string/1)
      value -> [to_string(value)]
    end
  end

  defp normalize_list(map, key) when is_map(map) do
    case normalize_value(map, key) do
      nil -> nil
      list when is_list(list) -> list
      value -> [value]
    end
  end

  defp normalize_items(definition) when is_map(definition) do
    case normalize_value(definition, :items) do
      nil -> nil
      items -> normalize_type_descriptor(items)
    end
  end

  defp normalize_type_descriptor(items) when is_map(items) do
    %{
      type: normalize_optional(items, :type),
      type_ref: normalize_type_ref(items),
      items: normalize_items(items),
      value: normalize_value(items, :value),
      choices: normalize_value(items, :choices)
    }
  end

  defp normalize_type_descriptor(items), do: %{type: normalize_key(items)}

  defp normalize_type_ref(definition) when is_map(definition) do
    normalize_optional(definition, :type_ref) ||
      normalize_optional(definition, :"$ref") ||
      normalize_optional(definition, :ref)
  end

  defp normalize_type_kind(definition) when is_map(definition) do
    case normalize_value(definition, :kind) || normalize_value(definition, :type) do
      "union" -> :union
      "object" -> :object
      "enum" -> :enum
      _ -> nil
    end
  end

  defp normalize_union_type(definition, description) do
    discriminator = normalize_union_discriminator(definition)

    %{
      kind: :union,
      description: description,
      discriminator: discriminator
    }
  end

  defp normalize_union_discriminator(definition) do
    disc = normalize_value(definition, :discriminator)
    variants = normalize_variants(definition) || %{}

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
    field = normalize_value(disc, :field) || "type"
    mapping = Map.get(disc, "mapping") || Map.get(disc, :mapping) || variants
    build_discriminator(normalize_key(field), mapping)
  end

  defp build_discriminator(field, mapping) do
    %{field: field, mapping: normalize_variant_mapping(mapping)}
  end

  defp normalize_variants(definition) do
    case normalize_value(definition, :variants) do
      nil -> nil
      variants when is_map(variants) -> variants
      variants when is_list(variants) -> normalize_variant_list(variants)
      _ -> nil
    end
  end

  defp normalize_variant_list(variants) do
    Enum.reduce(variants, %{}, fn variant, acc ->
      variant_value =
        normalize_value(variant, :discriminator_value) ||
          normalize_value(variant, :value) ||
          normalize_value(variant, :tag)

      type_ref = normalize_type_ref(variant) || normalize_optional(variant, :type)

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

  defp has_alias_type?(definition) when is_map(definition) do
    type = normalize_value(definition, :type)
    type_ref = normalize_type_ref(definition)
    value = normalize_value(definition, :value)
    choices = normalize_value(definition, :choices)

    not is_nil(type) or not is_nil(type_ref) or not is_nil(value) or not is_nil(choices)
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
