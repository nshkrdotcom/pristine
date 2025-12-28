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
      code = render_type_module(module_name, name, defn)
      {module_name, code}
    end)
    |> Map.new()
  end

  @doc """
  Renders a single type module with Sinter schema.
  """
  @spec render_type_module(String.t(), String.t(), map()) :: String.t()
  def render_type_module(module_name, type_name, type_def) do
    fields = get_fields(type_def)
    description = Map.get(type_def, "description") || "#{type_name} type."

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{description}
      \"\"\"

      defstruct #{render_defstruct_fields(fields)}

      @type t :: %__MODULE__{
    #{render_type_fields(fields)}  }

      @doc "Returns the Sinter schema for this type."
      @spec schema() :: Sinter.Schema.t()
      def schema do
        Sinter.Schema.define([
    #{render_schema_fields(fields)}    ])
      end

      @doc "Create a new #{type_name} from a map."
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

      @doc "Create a new #{type_name}."
      @spec new(keyword() | map()) :: t()
      def new(attrs \\\\ [])
      def new(attrs) when is_list(attrs), do: struct(__MODULE__, attrs)
      def new(attrs) when is_map(attrs), do: from_map(attrs)

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

  defp get_fields(type_def) do
    case Map.get(type_def, "fields") || Map.get(type_def, :fields) do
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

  defp render_defstruct_fields(fields) do
    field_names =
      fields
      |> Enum.map(fn field ->
        name = Map.get(field, "name") || Map.get(field, :name)
        String.to_atom(name)
      end)

    inspect(field_names)
  end

  defp render_type_fields(fields) do
    Enum.map_join(fields, ",\n", &render_type_field/1)
  end

  defp render_type_field(field) do
    {name, type_str, required, items} = extract_field_info(field)
    type_spec = build_typespec(type_str, items)
    type_with_nil = if required, do: type_spec, else: "#{type_spec} | nil"
    "      #{name}: #{type_with_nil}"
  end

  defp render_schema_fields(fields) do
    Enum.map_join(fields, ",\n", &render_schema_field/1)
  end

  defp render_schema_field(field) do
    {name, type_str, required, items} = extract_field_info(field)
    sinter_type = build_sinter_type(type_str, items)
    opts = if required, do: "[required: true]", else: "[optional: true]"
    "      {:#{name}, #{sinter_type}, #{opts}}"
  end

  defp extract_field_info(field) do
    name = get_field_value(field, "name")
    type_str = get_field_value(field, "type") || "any"
    required = get_field_value(field, "required") || false
    items = get_field_value(field, "items")
    {name, type_str, required, items}
  end

  defp get_field_value(field, key) do
    Map.get(field, key) || Map.get(field, String.to_atom(key))
  end

  defp build_typespec("array", items) when not is_nil(items) do
    "[#{map_type_to_typespec(items)}]"
  end

  defp build_typespec(type_str, _items), do: map_type_to_typespec(type_str)

  defp build_sinter_type("array", items) when not is_nil(items) do
    "{:array, #{map_type_to_sinter(items)}}"
  end

  defp build_sinter_type(type_str, _items), do: map_type_to_sinter(type_str)

  defp map_type_to_sinter("string"), do: ":string"
  defp map_type_to_sinter("integer"), do: ":integer"
  defp map_type_to_sinter("float"), do: ":float"
  defp map_type_to_sinter("number"), do: ":float"
  defp map_type_to_sinter("boolean"), do: ":boolean"
  defp map_type_to_sinter("map"), do: ":map"
  defp map_type_to_sinter("array"), do: "{:array, :any}"
  defp map_type_to_sinter(_), do: ":any"
end
