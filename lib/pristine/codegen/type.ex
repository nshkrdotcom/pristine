defmodule Pristine.Codegen.Type do
  @moduledoc """
  Generates type modules with Sinter schemas.

  Type modules provide structured data types with validation schemas,
  constructors, and serialization helpers.
  """

  @doc """
  Renders all type modules for a map of type definitions.

  Returns a map of module name to source code.
  """
  @spec render_all_type_modules(String.t(), map()) :: %{String.t() => String.t()}
  def render_all_type_modules(namespace, types) when is_map(types) do
    types
    |> Enum.map(fn {name, defn} ->
      module_name = "#{namespace}.#{name}"
      code = render_type_module(module_name, name, defn, types)
      {module_name, code}
    end)
    |> Map.new()
  end

  @doc """
  Renders a single type module with Sinter schema.
  """
  @spec render_type_module(String.t(), String.t(), map()) :: String.t()
  def render_type_module(module_name, type_name, type_def) do
    render_type_module(module_name, type_name, type_def, %{})
  end

  @spec render_type_module(String.t(), String.t(), map(), map()) :: String.t()
  def render_type_module(module_name, type_name, type_def, types) do
    base_namespace = base_namespace(module_name, type_name)
    description = get_value(type_def, "description") || "#{type_name} type."

    case type_kind(type_def) do
      :union ->
        render_union_module(module_name, description, type_def, base_namespace)

      :alias ->
        render_alias_module(module_name, description, type_def, base_namespace, types)

      _ ->
        render_object_module(module_name, description, type_def, types, base_namespace)
    end
  end

  @doc """
  Maps a type string to an Elixir typespec.
  """
  @spec map_type_to_typespec(String.t()) :: String.t()
  def map_type_to_typespec("string"), do: "String.t()"
  def map_type_to_typespec("integer"), do: "integer()"
  def map_type_to_typespec("float"), do: "float()"
  def map_type_to_typespec("number"), do: "number()"
  def map_type_to_typespec("boolean"), do: "boolean()"
  def map_type_to_typespec("map"), do: "map()"
  def map_type_to_typespec("array"), do: "list()"
  def map_type_to_typespec(_), do: "term()"

  # Private functions

  defp render_object_module(module_name, description, type_def, types, base_namespace) do
    fields = get_fields(type_def)
    ref_modes = field_ref_modes(fields, types, base_namespace)
    ref_helpers = render_ref_helpers(ref_modes)

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{description}
      \"\"\"

      defstruct #{render_defstruct_fields(fields)}

      @type t :: %__MODULE__{
    #{render_type_fields(fields, types, base_namespace)}  }

      @doc "Returns the Sinter schema for this type."
      @spec schema() :: Sinter.Schema.t()
      def schema do
        Sinter.Schema.define([
    #{render_schema_fields(fields, types, base_namespace)}    ])
      end

      @doc "Decode a map into a #{module_name} struct."
      @spec decode(map()) :: {:ok, t()} | {:error, term()}
      def decode(data) when is_map(data) do
        with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
    #{render_decode_body(fields, types, base_namespace)}    end
      end

      def decode(_), do: {:error, :invalid_input}

      @doc "Encode a #{module_name} struct into a map."
      @spec encode(t()) :: map()
      def encode(%__MODULE__{} = struct) do
        %{
    #{render_encode_fields(fields, types, base_namespace)}    }
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Map.new()
      end

      @doc "Create a new #{module_name} from a map."
      @spec from_map(map()) :: t()
      def from_map(data) when is_map(data) do
        struct(__MODULE__, atomize_keys(data))
      end

      @doc "Convert to a map."
      @spec to_map(t()) :: map()
      def to_map(%__MODULE__{} = struct) do
        struct
        |> Map.from_struct()
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Map.new()
      end

      @doc "Create a new #{module_name}."
      @spec new(keyword() | map()) :: t()
      def new(attrs \\\\ [])
      def new(attrs) when is_list(attrs), do: struct(__MODULE__, attrs)
      def new(attrs) when is_map(attrs), do: from_map(attrs)

    #{ref_helpers}
      defp atomize_keys(map) do
        Map.new(map, fn
          {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
          {k, v} when is_atom(k) -> {k, v}
        end)
      rescue
        ArgumentError -> map
      end
    end
    """
  end

  defp render_union_module(module_name, description, type_def, base_namespace) do
    discriminator = get_discriminator(type_def)
    variants = discriminator.mapping
    variant_modules = variants |> Map.values() |> Enum.uniq()
    aliases = render_aliases(variant_modules, base_namespace)

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{description}
      \"\"\"

    #{aliases}  @type t :: #{render_union_typespecs(variant_modules, base_namespace)}

      @doc "Returns the Sinter type spec for this union."
      @spec schema() :: Sinter.Types.type_spec()
      def schema do
        {:discriminated_union,
         discriminator: #{inspect(discriminator.field)},
         variants: #{render_union_variant_schemas(variants, base_namespace)}}
      end

      @doc "Decode a discriminated union value."
      @spec decode(map()) :: {:ok, t()} | {:error, term()}
      def decode(data) when is_map(data) do
        case fetch_discriminator(data) do
          nil ->
            {:error, :missing_discriminator}

    #{render_union_decode_clauses(variants, base_namespace)}          other ->
            {:error, {:unknown_variant, other}}
        end
      end

      def decode(_), do: {:error, :invalid_input}

      @doc "Encode a union value."
      @spec encode(t()) :: map()
      def encode(value) do
    #{render_union_encode_clauses(variant_modules, base_namespace)}
      end

      defp fetch_discriminator(data) do
        Map.get(data, #{inspect(discriminator.field)}) ||
          case safe_existing_atom(#{inspect(discriminator.field)}) do
            {:ok, atom} -> Map.get(data, atom)
            :error -> nil
          end
      end

      defp safe_existing_atom(value) do
        try do
          {:ok, String.to_existing_atom(to_string(value))}
        rescue
          ArgumentError -> :error
        end
      end
    end
    """
  end

  defp render_alias_module(module_name, description, type_def, base_namespace, types) do
    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{description}
      \"\"\"

      @type t :: #{render_alias_typespec(type_def, base_namespace)}

      @doc "Returns the Sinter type spec for this alias."
      @spec schema() :: Sinter.Types.type_spec()
      def schema do
        #{render_alias_schema(type_def, base_namespace, types)}
      end

      @doc "Decode a value for this alias type."
      @spec decode(term()) :: {:ok, t()} | {:error, term()}
      def decode(value) do
        Sinter.Types.validate(schema(), value)
      end

      @doc "Encode a value for this alias type."
      @spec encode(t()) :: term()
      def encode(value), do: value
    end
    """
  end

  defp render_defstruct_fields(fields) do
    field_names =
      fields
      |> Enum.map(fn field ->
        name = get_value(field, "name")
        String.to_atom(name)
      end)

    inspect(field_names)
  end

  defp render_type_fields(fields, types, base_namespace) do
    Enum.map_join(fields, ",\n", &render_type_field(&1, types, base_namespace))
  end

  defp render_type_field(field, types, base_namespace) do
    {name, type_spec, required} = extract_field_info(field, types, base_namespace)
    type_with_nil = if required, do: type_spec, else: "#{type_spec} | nil"
    "      #{name}: #{type_with_nil}"
  end

  defp render_schema_fields(fields, types, base_namespace) do
    Enum.map_join(fields, ",\n", &render_schema_field(&1, types, base_namespace))
  end

  defp render_schema_field(field, types, base_namespace) do
    name = get_value(field, "name")
    sinter_type = render_sinter_type(field, types, base_namespace)
    opts = render_schema_opts(field)
    "      {:#{name}, #{sinter_type}, #{opts}}"
  end

  defp render_schema_opts(field) do
    required = get_value(field, "required") || false

    []
    |> maybe_add_opt(:required, required)
    |> maybe_add_opt(:optional, not required)
    |> maybe_add_opt(:default, get_value(field, "default"))
    |> maybe_add_opt(:description, get_value(field, "description"))
    |> maybe_add_opt(:min_length, get_value(field, "min_length"))
    |> maybe_add_opt(:max_length, get_value(field, "max_length"))
    |> maybe_add_opt(:min_items, get_value(field, "min_items"))
    |> maybe_add_opt(:max_items, get_value(field, "max_items"))
    |> maybe_add_opt(:gt, get_value(field, "gt"))
    |> maybe_add_opt(:gteq, get_value(field, "gteq"))
    |> maybe_add_opt(:lt, get_value(field, "lt"))
    |> maybe_add_opt(:lteq, get_value(field, "lteq"))
    |> maybe_add_opt(:format, get_value(field, "format"))
    |> maybe_add_opt(:choices, get_value(field, "choices"))
    |> maybe_add_opt(:alias, get_value(field, "alias"))
    |> inspect()
  end

  defp render_decode_body(fields, types, base_namespace) do
    ref_assignments = render_decode_ref_assignments(fields, types, base_namespace)
    struct_fields = render_struct_fields(fields, types, base_namespace)

    if ref_assignments == "" do
      """
        {:ok, %__MODULE__{
      #{struct_fields}        }}
      """
    else
      """
        with #{ref_assignments} do
          {:ok, %__MODULE__{
      #{struct_fields}          }}
        end
      """
    end
  end

  defp render_decode_ref_assignments(fields, types, base_namespace) do
    fields
    |> Enum.map(&field_ref_info(&1, types, base_namespace))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {name, mode, module} ->
      ref_var = "#{name}_decoded"

      call =
        case mode do
          :single -> "decode_ref(validated[\"#{name}\"], #{module})"
          :list -> "decode_ref_list(validated[\"#{name}\"], #{module})"
        end

      "{:ok, #{ref_var}} <- #{call}"
    end)
    |> case do
      [] -> ""
      clauses -> Enum.join(clauses, ",\n             ")
    end
  end

  defp render_struct_fields(fields, types, base_namespace) do
    Enum.map_join(fields, ",\n", fn field ->
      name = get_value(field, "name")

      value =
        case field_ref_info(field, types, base_namespace) do
          {^name, _mode, _module} -> "#{name}_decoded"
          _ -> "validated[\"#{name}\"]"
        end

      "          #{name}: #{value}"
    end)
  end

  defp render_encode_fields(fields, types, base_namespace) do
    Enum.map_join(fields, ",\n", fn field ->
      name = get_value(field, "name")

      field_expr =
        case field_ref_info(field, types, base_namespace) do
          {^name, :single, module} -> "encode_ref(struct.#{name}, #{module})"
          {^name, :list, module} -> "encode_ref_list(struct.#{name}, #{module})"
          _ -> "struct.#{name}"
        end

      "          \"#{name}\" => #{field_expr}"
    end)
  end

  defp render_union_variant_schemas(variants, base_namespace) do
    entries =
      Enum.map(variants, fn {disc_value, type_name} ->
        module = "#{base_namespace}.#{type_name}"
        "\"#{disc_value}\" => #{module}.schema()"
      end)

    "%{#{Enum.join(entries, ", ")}}"
  end

  defp render_union_decode_clauses(variants, base_namespace) do
    Enum.map_join(variants, "\n", fn {disc_value, type_name} ->
      module = "#{base_namespace}.#{type_name}"
      "          \"#{disc_value}\" -> #{module}.decode(data)\n"
    end)
  end

  defp render_union_encode_clauses(variant_modules, base_namespace) do
    clauses =
      Enum.map_join(variant_modules, "\n", fn type_name ->
        module = "#{base_namespace}.#{type_name}"
        "      %#{module}{} = value -> #{module}.encode(value)"
      end)

    if clauses == "" do
      "    value\n"
    else
      "    case value do\n#{clauses}\n      _ -> value\n    end\n"
    end
  end

  defp render_union_typespecs([], _base_namespace), do: "term()"

  defp render_union_typespecs(variant_modules, base_namespace) do
    variant_modules
    |> Enum.map_join(" | ", fn type_name -> "#{base_namespace}.#{type_name}.t()" end)
  end

  defp render_aliases([], _base_namespace), do: ""

  defp render_aliases(variant_modules, base_namespace) do
    modules =
      Enum.map_join(variant_modules, ", ", fn type_name -> "#{base_namespace}.#{type_name}" end)

    "  alias #{modules}\n\n"
  end

  defp render_alias_typespec(type_def, base_namespace) do
    type_ref = get_value(type_def, "type_ref")
    value = get_value(type_def, "value")
    choices = get_value(type_def, "choices")
    type = get_value(type_def, "type")
    items = get_value(type_def, "items")

    cond do
      type_ref ->
        "#{base_namespace}.#{type_ref}.t()"

      is_list(choices) ->
        "term()"

      not is_nil(value) ->
        literal_typespec(value)

      normalize_key(type) == "array" ->
        "[#{render_alias_item_typespec(items, base_namespace)}]"

      true ->
        map_type_to_typespec(normalize_key(type || "term"))
    end
  end

  defp render_alias_item_typespec(items, base_namespace) when is_map(items) do
    type_ref = get_value(items, "type_ref")
    type = get_value(items, "type")

    if type_ref do
      "#{base_namespace}.#{type_ref}.t()"
    else
      map_type_to_typespec(normalize_key(type || "term"))
    end
  end

  defp render_alias_item_typespec(items, _base_namespace) do
    map_type_to_typespec(normalize_key(items || "term"))
  end

  defp render_alias_schema(type_def, base_namespace, types) do
    type_ref = get_value(type_def, "type_ref")
    value = get_value(type_def, "value")
    choices = get_value(type_def, "choices")
    type = get_value(type_def, "type")
    items = get_value(type_def, "items")

    cond do
      type_ref ->
        render_alias_ref_schema(type_ref, base_namespace, types)

      is_list(choices) ->
        "{:union, #{inspect(Enum.map(choices, &{:literal, &1}))}}"

      not is_nil(value) ->
        "{:literal, #{inspect(value)}}"

      normalize_key(type) == "array" ->
        "{:array, #{render_alias_item_schema(items, base_namespace, types)}}"

      true ->
        map_type_to_sinter(normalize_key(type || "any"))
    end
  end

  defp render_alias_item_schema(items, base_namespace, types) when is_map(items) do
    type_ref = get_value(items, "type_ref")
    type = get_value(items, "type")

    cond do
      type_ref ->
        render_alias_ref_schema(type_ref, base_namespace, types)

      type_defined?(type, types) ->
        render_alias_ref_schema(type, base_namespace, types)

      true ->
        map_type_to_sinter(normalize_key(type || "any"))
    end
  end

  defp render_alias_item_schema(items, _base_namespace, _types) do
    map_type_to_sinter(normalize_key(items || "any"))
  end

  defp extract_field_info(field, types, base_namespace) do
    name = get_value(field, "name")
    required = get_value(field, "required") || false
    type_spec = build_typespec(field, types, base_namespace)
    {name, type_spec, required}
  end

  defp build_typespec(field, types, base_namespace) do
    type_ref = get_value(field, "type_ref")
    type = get_value(field, "type") || "any"
    items = get_value(field, "items")
    value = get_value(field, "value")

    cond do
      type_ref ->
        "#{base_namespace}.#{type_ref}.t()"

      normalize_key(type) == "array" ->
        "[#{build_item_typespec(items, types, base_namespace)}]"

      normalize_key(type) == "literal" ->
        literal_typespec(value)

      true ->
        map_type_to_typespec(normalize_key(type))
    end
  end

  defp build_item_typespec(items, types, base_namespace) when is_map(items) do
    type_ref = get_value(items, "type_ref")
    type = get_value(items, "type")

    cond do
      type_ref ->
        "#{base_namespace}.#{type_ref}.t()"

      type_defined?(type, types) ->
        "#{base_namespace}.#{type}.t()"

      true ->
        map_type_to_typespec(normalize_key(type || "term"))
    end
  end

  defp build_item_typespec(items, types, base_namespace) do
    if type_defined?(items, types) do
      "#{base_namespace}.#{items}.t()"
    else
      map_type_to_typespec(normalize_key(items || "term"))
    end
  end

  defp render_sinter_type(field, types, base_namespace) do
    type_ref = get_value(field, "type_ref")
    type = get_value(field, "type") || "any"
    items = get_value(field, "items")
    value = get_value(field, "value")

    cond do
      type_ref ->
        render_ref_sinter_type(type_ref, types, base_namespace)

      normalize_key(type) == "array" ->
        "{:array, #{render_item_sinter_type(items, types, base_namespace)}}"

      normalize_key(type) == "literal" ->
        "{:literal, #{inspect(value)}}"

      true ->
        map_type_to_sinter(normalize_key(type))
    end
  end

  defp render_ref_sinter_type(type_ref, types, base_namespace) do
    ref_def = Map.get(types, type_ref) || Map.get(types, normalize_key(type_ref)) || %{}

    case type_kind(ref_def) do
      :union -> "#{base_namespace}.#{type_ref}.schema()"
      :alias -> "#{base_namespace}.#{type_ref}.schema()"
      _ -> "{:object, #{base_namespace}.#{type_ref}.schema()}"
    end
  end

  defp render_alias_ref_schema(type_ref, base_namespace, types) do
    ref_def = Map.get(types, type_ref) || Map.get(types, normalize_key(type_ref)) || %{}

    case type_kind(ref_def) do
      :object -> "{:object, #{base_namespace}.#{type_ref}.schema()}"
      _ -> "#{base_namespace}.#{type_ref}.schema()"
    end
  end

  defp render_item_sinter_type(items, types, base_namespace) when is_map(items) do
    type_ref = get_value(items, "type_ref")
    type = get_value(items, "type")

    cond do
      type_ref ->
        render_ref_sinter_type(type_ref, types, base_namespace)

      type_defined?(type, types) ->
        render_ref_sinter_type(type, types, base_namespace)

      true ->
        map_type_to_sinter(normalize_key(type || "any"))
    end
  end

  defp render_item_sinter_type(items, types, base_namespace) do
    if type_defined?(items, types) do
      render_ref_sinter_type(items, types, base_namespace)
    else
      map_type_to_sinter(normalize_key(items || "any"))
    end
  end

  defp field_ref_info(field, types, base_namespace) do
    name = get_value(field, "name")
    type_ref = get_value(field, "type_ref")
    type = normalize_key(get_value(field, "type") || "")
    items = get_value(field, "items")

    cond do
      type_ref ->
        {name, :single, "#{base_namespace}.#{type_ref}"}

      type == "array" and is_map(items) and get_value(items, "type_ref") ->
        {name, :list, "#{base_namespace}.#{get_value(items, "type_ref")}"}

      type == "array" and type_defined?(items, types) ->
        {name, :list, "#{base_namespace}.#{items}"}

      true ->
        nil
    end
  end

  defp field_ref_modes(fields, types, base_namespace) do
    fields
    |> Enum.map(&field_ref_info(&1, types, base_namespace))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&elem(&1, 1))
    |> MapSet.new()
  end

  defp render_ref_helpers(ref_modes) do
    if MapSet.size(ref_modes) == 0 do
      ""
    else
      list_helpers =
        if MapSet.member?(ref_modes, :list) do
          """
          defp decode_ref_list(nil, _module), do: {:ok, nil}
          defp decode_ref_list(values, module) when is_list(values) do
            Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
              case decode_ref(value, module) do
                {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
                {:error, _} = error -> {:halt, error}
              end
            end)
            |> case do
              {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
              {:error, _} = error -> error
            end
          end

          defp encode_ref_list(nil, _module), do: nil
          defp encode_ref_list(values, module) when is_list(values) do
            Enum.map(values, &encode_ref(&1, module))
          end

          """
        else
          ""
        end

      """
      defp decode_ref(nil, _module), do: {:ok, nil}
      defp decode_ref(value, module) do
        if function_exported?(module, :decode, 1) do
          module.decode(value)
        else
          {:ok, value}
        end
      end

      defp encode_ref(nil, _module), do: nil
      defp encode_ref(value, module) do
        if function_exported?(module, :encode, 1) do
          module.encode(value)
        else
          value
        end
      end

      #{list_helpers}
      """
    end
  end

  defp get_fields(type_def) do
    case get_value(type_def, "fields") do
      fields when is_list(fields) -> fields
      fields when is_map(fields) -> convert_map_fields(fields)
      _ -> []
    end
  end

  defp convert_map_fields(fields) do
    Enum.map(fields, fn {name, defn} ->
      normalize_field_def(defn, to_string(name))
    end)
  end

  defp normalize_field_def(defn, name) when is_map(defn) do
    Map.put(defn, "name", name)
  end

  defp normalize_field_def(type, name) when is_binary(type) do
    %{"name" => name, "type" => type, "required" => false}
  end

  defp normalize_field_def(_, name) do
    %{"name" => name, "type" => "any", "required" => false}
  end

  defp base_namespace(module_name, type_name) do
    String.replace_suffix(module_name, ".#{type_name}", "")
  end

  defp get_discriminator(type_def) do
    disc = get_value(type_def, "discriminator") || %{}
    field = get_value(disc, "field") || "type"
    mapping = get_value(disc, "mapping") || %{}

    %{
      field: to_string(field),
      mapping: normalize_variant_mapping(mapping)
    }
  end

  defp normalize_variant_mapping(mapping) when is_map(mapping) do
    Enum.reduce(mapping, %{}, fn {k, v}, acc ->
      Map.put(acc, to_string(k), to_string(v))
    end)
  end

  defp normalize_variant_mapping(_), do: %{}

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, false), do: opts
  defp maybe_add_opt(opts, key, true), do: Keyword.put(opts, key, true)
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp get_value(field, key) do
    Map.get(field, key) || Map.get(field, String.to_atom(key))
  end

  defp type_kind(type_def) when is_map(type_def) do
    kind = get_value(type_def, "kind") || get_value(type_def, "type")

    cond do
      kind in [:union, "union"] -> :union
      kind in [:alias, "alias"] -> :alias
      kind in [:object, "object"] -> :object
      get_value(type_def, "fields") != nil -> :object
      alias_definition?(type_def) -> :alias
      true -> :object
    end
  end

  defp type_kind(_), do: :object

  defp alias_definition?(type_def) do
    get_value(type_def, "type") ||
      get_value(type_def, "type_ref") ||
      get_value(type_def, "value") ||
      get_value(type_def, "choices")
  end

  defp literal_typespec(value) when is_integer(value), do: "integer()"
  defp literal_typespec(value) when is_float(value), do: "float()"
  defp literal_typespec(value) when is_boolean(value), do: "boolean()"
  defp literal_typespec(value) when is_binary(value), do: "String.t()"
  defp literal_typespec(_value), do: "term()"

  defp map_type_to_sinter("string"), do: ":string"
  defp map_type_to_sinter("integer"), do: ":integer"
  defp map_type_to_sinter("float"), do: ":float"
  defp map_type_to_sinter("number"), do: ":float"
  defp map_type_to_sinter("boolean"), do: ":boolean"
  defp map_type_to_sinter("map"), do: ":map"
  defp map_type_to_sinter("array"), do: "{:array, :any}"
  defp map_type_to_sinter(_), do: ":any"

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp type_defined?(type_name, types) when is_binary(type_name) do
    Map.has_key?(types, type_name) || Map.has_key?(types, normalize_key(type_name))
  end

  defp type_defined?(_type_name, _types), do: false
end
