defmodule Pristine.Test.Fixtures do
  @moduledoc """
  Generates test fixtures from Pristine manifest type definitions.

  This module provides utilities for generating realistic test data from
  schema definitions, enabling easy testing of generated clients.

  ## Usage

      # Generate a single fixture
      fixture = Fixtures.generate(schema)

      # Generate with seed for reproducibility
      fixture = Fixtures.generate(schema, seed: 12345)

      # Generate list of fixtures
      fixtures = Fixtures.generate_list(schema, 10)

      # Generate fixtures for all manifest types
      fixtures = Fixtures.for_manifest(manifest)

      # Generate sample manifest for testing
      manifest = Fixtures.sample_manifest()

  """

  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint

  @type option :: {:seed, integer()} | {:include_optional, boolean()}

  @doc """
  Generates a fixture from a schema definition.

  ## Parameters

    * `schema` - A schema map with `:type` and optional constraints
    * `opts` - Generation options

  ## Options

    * `:seed` - Random seed for reproducible generation
    * `:include_optional` - Whether to include optional fields (default: true)

  ## Examples

      iex> Fixtures.generate(%{type: :string})
      "abc123"

      iex> Fixtures.generate(%{type: :integer, minimum: 1, maximum: 10})
      5

  """
  @spec generate(map(), [option]) :: term()
  def generate(schema, opts \\ []) do
    state = init_state(opts)
    {value, _state} = do_generate(schema, state)
    value
  end

  @doc """
  Generates a list of fixtures from a schema.

  ## Parameters

    * `schema` - A schema map
    * `count` - Number of fixtures to generate
    * `opts` - Generation options

  ## Examples

      iex> Fixtures.generate_list(%{type: :string}, 5)
      ["abc", "def", "ghi", "jkl", "mno"]

  """
  @spec generate_list(map(), pos_integer(), [option]) :: [term()]
  def generate_list(schema, count, opts \\ []) do
    state = init_state(opts)

    {fixtures, _state} =
      Enum.reduce(1..count, {[], state}, fn _, {acc, s} ->
        {value, new_state} = do_generate(schema, s)
        {[value | acc], new_state}
      end)

    Enum.reverse(fixtures)
  end

  @doc """
  Generates fixtures for all types defined in a manifest.

  ## Parameters

    * `manifest` - A loaded Pristine manifest
    * `opts` - Generation options

  ## Returns

    * A map of type names to generated fixtures

  ## Examples

      fixtures = Fixtures.for_manifest(manifest)
      user_fixture = fixtures["User"]

  """
  @spec for_manifest(Manifest.t(), [option]) :: %{String.t() => term()}
  def for_manifest(%Manifest{types: types}, opts \\ []) do
    state = init_state(opts)

    {fixtures, _state} =
      Enum.reduce(types, {%{}, state}, fn {type_name, type_def}, {acc, s} ->
        schema = type_def_to_schema(type_def)
        {value, new_state} = do_generate(schema, s)
        {Map.put(acc, type_name, value), new_state}
      end)

    fixtures
  end

  @doc """
  Generates request and response fixtures for an endpoint.

  ## Parameters

    * `manifest` - A loaded Pristine manifest
    * `endpoint` - An endpoint from the manifest
    * `opts` - Generation options

  ## Returns

    * A map with `:request` and `:response` fixtures

  ## Examples

      fixtures = Fixtures.for_endpoint(manifest, endpoint)
      request_data = fixtures.request
      response_data = fixtures.response

  """
  @spec for_endpoint(Manifest.t(), Endpoint.t(), [option]) :: %{request: term(), response: term()}
  def for_endpoint(%Manifest{} = manifest, %Endpoint{} = endpoint, opts \\ []) do
    state = init_state(opts)

    {request_fixture, state} =
      if endpoint.request do
        type_def = find_type(manifest, endpoint.request)

        if type_def do
          schema = type_def_to_schema(type_def)
          do_generate(schema, state)
        else
          {nil, state}
        end
      else
        {nil, state}
      end

    {response_fixture, _state} =
      if endpoint.response do
        type_def = find_type(manifest, endpoint.response)

        if type_def do
          schema = type_def_to_schema(type_def)
          do_generate(schema, state)
        else
          {nil, state}
        end
      else
        {nil, state}
      end

    %{request: request_fixture, response: response_fixture}
  end

  @doc """
  Creates a sample manifest for testing purposes.

  ## Parameters

    * `overrides` - Keyword list of attributes to override

  ## Returns

    * A valid Manifest struct

  ## Examples

      manifest = Fixtures.sample_manifest()
      manifest = Fixtures.sample_manifest(name: "MyAPI", version: "2.0.0")

  """
  @spec sample_manifest(keyword()) :: Manifest.t()
  def sample_manifest(overrides \\ []) do
    name = Keyword.get(overrides, :name, "SampleAPI")
    version = Keyword.get(overrides, :version, "1.0.0")

    input = %{
      name: name,
      version: version,
      endpoints: [
        %{
          id: "get_item",
          method: "GET",
          path: "/items/{id}",
          response: "Item"
        },
        %{
          id: "create_item",
          method: "POST",
          path: "/items",
          request: "ItemCreate",
          response: "Item"
        }
      ],
      types: %{
        "Item" => %{
          fields: %{
            id: %{type: "string", required: true},
            name: %{type: "string", required: true},
            created_at: %{type: "string", required: false}
          }
        },
        "ItemCreate" => %{
          fields: %{
            name: %{type: "string", required: true}
          }
        }
      }
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end

  # Private functions - State management

  defp init_state(opts) do
    seed = Keyword.get(opts, :seed)
    include_optional = Keyword.get(opts, :include_optional, true)

    # Initialize random state
    rng_state =
      if seed do
        :rand.seed(:exsss, {seed, seed, seed})
      else
        :rand.seed(:exsss)
      end

    %{
      rng: rng_state,
      include_optional: include_optional,
      counter: 0
    }
  end

  # Private functions - Generation

  defp do_generate(%{type: :string} = schema, state) do
    min_len = Map.get(schema, :min_length, 5)
    max_len = Map.get(schema, :max_length, 20)

    {length, state} = random_int(min_len, max_len, state)
    {str, state} = random_string(length, state)
    {str, state}
  end

  defp do_generate(%{type: :integer} = schema, state) do
    min = Map.get(schema, :minimum, 1)
    max = Map.get(schema, :maximum, 1000)
    random_int(min, max, state)
  end

  defp do_generate(%{type: :number} = schema, state) do
    min = Map.get(schema, :minimum, 0.0)
    max = Map.get(schema, :maximum, 1000.0)
    random_float(min, max, state)
  end

  defp do_generate(%{type: :boolean}, state) do
    {n, state} = random_int(0, 1, state)
    {n == 1, state}
  end

  defp do_generate(%{type: {:array, item_type}} = schema, state) do
    min_items = Map.get(schema, :min_items, 1)
    max_items = Map.get(schema, :max_items, 5)

    {count, state} = random_int(min_items, max_items, state)

    {items, state} =
      Enum.reduce(1..count, {[], state}, fn _, {acc, s} ->
        {item, new_state} = do_generate(%{type: item_type}, s)
        {[item | acc], new_state}
      end)

    {Enum.reverse(items), state}
  end

  defp do_generate(%{type: {:literal, value}}, state) do
    {value, state}
  end

  defp do_generate(%{type: {:union, types}}, state) do
    {index, state} = random_int(0, length(types) - 1, state)
    type = Enum.at(types, index)
    do_generate(%{type: type}, state)
  end

  defp do_generate(%{type: {:discriminated_union, opts}}, state) do
    discriminator = Keyword.fetch!(opts, :discriminator)
    variants = Keyword.fetch!(opts, :variants)

    keys = Map.keys(variants)
    {index, state} = random_int(0, length(keys) - 1, state)
    selected_key = Enum.at(keys, index)
    variant_schema = Map.fetch!(variants, selected_key)

    {value, state} = do_generate(variant_schema, state)
    {Map.put(value, to_string(discriminator), to_string(selected_key)), state}
  end

  defp do_generate(%{type: :map, properties: props}, state) do
    {map, state} =
      Enum.reduce(props, {%{}, state}, fn {name, type, opts}, {acc, s} ->
        required = Keyword.get(opts, :required, false)

        if required or s.include_optional do
          {value, new_state} = do_generate(%{type: type}, s)
          {Map.put(acc, to_string(name), value), new_state}
        else
          {acc, s}
        end
      end)

    {map, state}
  end

  defp do_generate(%{type: type_ref}, state) when is_atom(type_ref) do
    # Type reference - generate based on primitive type
    case type_ref do
      :string -> do_generate(%{type: :string}, state)
      :integer -> do_generate(%{type: :integer}, state)
      :number -> do_generate(%{type: :number}, state)
      :boolean -> do_generate(%{type: :boolean}, state)
      _ -> {%{"_type" => to_string(type_ref)}, state}
    end
  end

  defp do_generate(_schema, state) do
    # Default to string for unknown schemas
    do_generate(%{type: :string}, state)
  end

  # Private functions - Random generation

  defp random_int(min, max, state) when min == max, do: {min, state}

  defp random_int(min, max, state) do
    range = max - min + 1
    {n, new_rng} = :rand.uniform_s(range, state.rng)
    value = n + min - 1
    {value, %{state | rng: new_rng, counter: state.counter + 1}}
  end

  defp random_float(min, max, state) do
    {n, new_rng} = :rand.uniform_s(state.rng)
    value = min + n * (max - min)
    {value, %{state | rng: new_rng, counter: state.counter + 1}}
  end

  defp random_string(length, state) when length <= 0 do
    {"", state}
  end

  defp random_string(length, state) do
    chars = ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    chars_count = length(chars)

    {chars_list, state} =
      Enum.reduce(1..length, {[], state}, fn _, {acc, s} ->
        {idx, new_state} = random_int(0, chars_count - 1, s)
        char = Enum.at(chars, idx)
        {[char | acc], new_state}
      end)

    {to_string(Enum.reverse(chars_list)), state}
  end

  # Private functions - Helpers

  defp find_type(%Manifest{types: types}, type_id) do
    Map.get(types, type_id)
  end

  defp type_def_to_schema(%{fields: fields}) when is_map(fields) do
    properties =
      Enum.map(fields, fn {name, field_def} ->
        type = get_field_type(field_def)
        required = field_required?(field_def)
        {name, type, [required: required]}
      end)

    %{type: :map, properties: properties}
  end

  defp type_def_to_schema(_), do: %{type: :map, properties: []}

  defp get_field_type(field_def) when is_map(field_def) do
    type_str = Map.get(field_def, :type) || Map.get(field_def, "type") || "string"
    parse_type_string(type_str)
  end

  defp get_field_type(_), do: :string

  defp parse_type_string(t) when is_atom(t), do: t
  defp parse_type_string("string"), do: :string
  defp parse_type_string("integer"), do: :integer
  defp parse_type_string("number"), do: :number
  defp parse_type_string("boolean"), do: :boolean
  defp parse_type_string("array"), do: {:array, :string}
  defp parse_type_string(_), do: :string

  defp field_required?(field_def) when is_map(field_def) do
    Map.get(field_def, :required) == true or Map.get(field_def, "required") == true
  end

  defp field_required?(_), do: false
end
