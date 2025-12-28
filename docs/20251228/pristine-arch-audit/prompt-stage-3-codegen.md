# Stage 3: Codegen Enhancement Implementation Prompt

**Estimated Effort**: 5-7 days
**Prerequisites**: Stage 1 Complete (Type System)
**Goal**: All tests pass, no warnings, no errors, no dialyzer errors, no `mix credo --strict` errors

---

## Context

You are implementing Stage 3 of the Pristine architecture buildout. This stage focuses on enhancing the code generator to produce SDK-quality Elixir code with:

- Resource module grouping (like `client.models.create()`)
- Type module generation with Sinter schemas
- Client module with resource accessors
- Full documentation and typespecs

---

## Required Reading

### Architecture Documentation
```
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/overview.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/02-client-resource-mapping.md
```

### Pristine Source Files
```
/home/home/p/g/n/pristine/lib/pristine/codegen.ex
/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex
/home/home/p/g/n/pristine/lib/pristine/manifest.ex
/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex
```

### Reference: Tinker Resource Pattern
```
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_resource.py
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/models.py
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/sampling.py
```

### Reference: Tinkex Elixir Structure
```
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/models.ex
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/sampling.ex
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/sample_request.ex
```

---

## Tasks

### Task 3.1: Add Resource Field to Endpoint (0.5 day)

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex`
- `/home/home/p/g/n/pristine/lib/pristine/manifest/schema.ex`

**Changes**:

```elixir
# In endpoint.ex
defstruct [
  # ... existing fields ...
  resource: nil  # NEW: Resource group name (e.g., "models", "sampling")
]

@type t :: %__MODULE__{
  # ... existing types ...
  resource: String.t() | nil
}
```

Update the manifest schema to validate the `resource` field.

---

### Task 3.2: Resource Module Generation (2-3 days)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/codegen/resource.ex`
- `/home/home/p/g/n/pristine/test/pristine/codegen/resource_test.exs`

**TDD Steps**:

1. **Write Tests First**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/codegen/resource_test.exs
defmodule Pristine.Codegen.ResourceTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen.Resource
  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint

  describe "group_by_resource/1" do
    test "groups endpoints by resource field" do
      endpoints = [
        %Endpoint{id: :create_model, resource: "models"},
        %Endpoint{id: :get_model, resource: "models"},
        %Endpoint{id: :sample, resource: "sampling"},
        %Endpoint{id: :health, resource: nil}
      ]

      grouped = Resource.group_by_resource(endpoints)

      assert Map.has_key?(grouped, "models")
      assert Map.has_key?(grouped, "sampling")
      assert Map.has_key?(grouped, nil)
      assert length(grouped["models"]) == 2
      assert length(grouped["sampling"]) == 1
    end
  end

  describe "render_resource_module/3" do
    test "generates module with all endpoint functions" do
      endpoints = [
        %Endpoint{
          id: :create,
          method: :post,
          path: "/api/v1/models",
          resource: "models",
          description: "Create a new model",
          request: "CreateModelRequest",
          response: "Model"
        },
        %Endpoint{
          id: :get,
          method: :get,
          path: "/api/v1/models/:id",
          resource: "models",
          description: "Get a model by ID"
        }
      ]

      code = Resource.render_resource_module("MyAPI.Models", "models", endpoints)

      # Module definition
      assert code =~ "defmodule MyAPI.Models do"

      # Module doc
      assert code =~ "@moduledoc"
      assert code =~ "models"

      # Both functions
      assert code =~ "def create("
      assert code =~ "def get("

      # Docs
      assert code =~ "Create a new model"
      assert code =~ "Get a model by ID"
    end

    test "generates with_client/1 function" do
      endpoints = [%Endpoint{id: :test, resource: "test"}]

      code = Resource.render_resource_module("MyAPI.Test", "test", endpoints)

      assert code =~ "def with_client(%{context: context})"
      assert code =~ "%__MODULE__{context: context}"
    end

    test "includes @manifest module attribute" do
      endpoints = [%Endpoint{id: :test, resource: "test"}]

      code = Resource.render_resource_module("MyAPI.Test", "test", endpoints)

      assert code =~ "@manifest"
    end
  end

  describe "render_all_resource_modules/2" do
    test "generates one module per resource" do
      manifest = %Manifest{
        name: "TestAPI",
        version: "1.0.0",
        endpoints: [
          %Endpoint{id: :create_model, resource: "models"},
          %Endpoint{id: :sample, resource: "sampling"}
        ],
        types: %{}
      }

      modules = Resource.render_all_resource_modules("TestAPI", manifest)

      assert Map.has_key?(modules, "TestAPI.Models")
      assert Map.has_key?(modules, "TestAPI.Sampling")
    end

    test "capitalizes resource name for module" do
      manifest = %Manifest{
        name: "TestAPI",
        version: "1.0.0",
        endpoints: [
          %Endpoint{id: :test, resource: "my_resource"}
        ],
        types: %{}
      }

      modules = Resource.render_all_resource_modules("TestAPI", manifest)

      assert Map.has_key?(modules, "TestAPI.MyResource")
    end
  end
end
```

2. **Implement Resource Module Generator**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/codegen/resource.ex
defmodule Pristine.Codegen.Resource do
  @moduledoc """
  Generates resource modules for grouped endpoints.
  """

  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint

  @doc "Groups endpoints by their resource field."
  @spec group_by_resource([Endpoint.t()]) :: %{String.t() | nil => [Endpoint.t()]}
  def group_by_resource(endpoints) do
    Enum.group_by(endpoints, & &1.resource)
  end

  @doc "Renders all resource modules for a manifest."
  @spec render_all_resource_modules(String.t(), Manifest.t()) :: %{String.t() => String.t()}
  def render_all_resource_modules(namespace, %Manifest{endpoints: endpoints} = manifest) do
    endpoints
    |> group_by_resource()
    |> Enum.reject(fn {resource, _} -> is_nil(resource) end)
    |> Enum.map(fn {resource, eps} ->
      module_name = resource_to_module_name(namespace, resource)
      code = render_resource_module(module_name, resource, eps, manifest)
      {module_name, code}
    end)
    |> Map.new()
  end

  @doc "Renders a single resource module."
  @spec render_resource_module(String.t(), String.t(), [Endpoint.t()], Manifest.t() | nil) :: String.t()
  def render_resource_module(module_name, resource, endpoints, manifest \\ nil) do
    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{String.capitalize(resource)} resource endpoints.

      This module provides functions for interacting with #{resource} resources.
      \"\"\"

      #{if manifest, do: "@manifest #{inspect(manifest, pretty: true, limit: :infinity)}", else: ""}

      defstruct [:context]

      @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

      @doc "Create a resource module instance with the given client."
      @spec with_client(%{context: Pristine.Core.Context.t()}) :: t()
      def with_client(%{context: context}) do
        %__MODULE__{context: context}
      end

    #{render_endpoint_functions(endpoints)}
    end
    """
  end

  defp render_endpoint_functions(endpoints) do
    endpoints
    |> Enum.map(&render_endpoint_function/1)
    |> Enum.join("\n")
  end

  defp render_endpoint_function(%Endpoint{} = endpoint) do
    fn_name = endpoint.id
    doc = render_doc(endpoint)
    spec = render_spec(fn_name, endpoint)

    """
    #{doc}#{spec}  def #{fn_name}(%__MODULE__{context: context}, payload, opts \\\\ []) do
        Pristine.Runtime.execute(context, #{inspect(endpoint.id)}, payload, opts)
      end

      @doc false
      def #{fn_name}(payload, context, opts) when is_map(payload) do
        Pristine.Runtime.execute(context, #{inspect(endpoint.id)}, payload, opts)
      end
    """
  end

  defp render_doc(%Endpoint{description: nil}), do: ""
  defp render_doc(%Endpoint{description: ""}), do: ""

  defp render_doc(%Endpoint{description: desc}) do
    """
      @doc \"\"\"
      #{String.trim(desc)}
      \"\"\"
    """
  end

  defp render_spec(fn_name, %Endpoint{}) do
    """
      @spec #{fn_name}(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
    """
  end

  defp resource_to_module_name(namespace, resource) do
    module_part = resource
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()

    "#{namespace}.#{module_part}"
  end
end
```

---

### Task 3.3: Client Module with Resource Accessors (1-2 days)

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex`

**Files to Create**:
- `/home/home/p/g/n/pristine/test/pristine/codegen/client_test.exs`

**TDD Steps**:

1. **Write Tests**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/codegen/client_test.exs
defmodule Pristine.Codegen.ClientTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen.Elixir, as: ElixirCodegen
  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint

  describe "render_client_module/2 with resources" do
    test "generates resource accessor functions" do
      manifest = %Manifest{
        name: "TestAPI",
        version: "1.0.0",
        endpoints: [
          %Endpoint{id: :create, resource: "models"},
          %Endpoint{id: :sample, resource: "sampling"}
        ],
        types: %{}
      }

      code = ElixirCodegen.render_client_module("TestAPI.Client", manifest)

      # Resource accessors
      assert code =~ "def models(%__MODULE__{} = client)"
      assert code =~ "def sampling(%__MODULE__{} = client)"

      # Returns resource module instance
      assert code =~ "TestAPI.Models.with_client(client)"
      assert code =~ "TestAPI.Sampling.with_client(client)"
    end

    test "generates new/1 constructor" do
      manifest = %Manifest{
        name: "TestAPI",
        version: "1.0.0",
        endpoints: [],
        types: %{}
      }

      code = ElixirCodegen.render_client_module("TestAPI.Client", manifest)

      assert code =~ "def new(opts \\\\ [])"
      assert code =~ "Context.build(opts)"
    end

    test "generates defstruct with context" do
      manifest = %Manifest{
        name: "TestAPI",
        version: "1.0.0",
        endpoints: [],
        types: %{}
      }

      code = ElixirCodegen.render_client_module("TestAPI.Client", manifest)

      assert code =~ "defstruct [:context]"
    end

    test "includes ungrouped endpoints directly in client" do
      manifest = %Manifest{
        name: "TestAPI",
        version: "1.0.0",
        endpoints: [
          %Endpoint{id: :health, resource: nil, path: "/health"}
        ],
        types: %{}
      }

      code = ElixirCodegen.render_client_module("TestAPI.Client", manifest)

      assert code =~ "def health("
    end
  end
end
```

2. **Update Elixir Codegen**:

```elixir
# Update /home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex

def render_client_module(module_name, %Manifest{} = manifest) do
  resources = get_unique_resources(manifest.endpoints)
  ungrouped_endpoints = get_ungrouped_endpoints(manifest.endpoints)

  """
  defmodule #{module_name} do
    @moduledoc \"\"\"
    Generated API client for #{manifest.name} v#{manifest.version}.

    ## Usage

        client = #{module_name}.new(api_key: "your-key")
        {:ok, result} = client |> #{module_name}.models() |> Models.create(payload)

    \"\"\"

    alias Pristine.Core.Context

    defstruct [:context]

    @type t :: %__MODULE__{context: Context.t()}

    @manifest #{inspect(manifest, pretty: true, limit: :infinity)}

    @doc "Returns the manifest used to generate this client."
    @spec manifest() :: Pristine.Manifest.t()
    def manifest, do: @manifest

    @doc \"\"\"
    Create a new client instance.

    ## Options

      * `:api_key` - API key for authentication
      * `:base_url` - Override the default base URL
      * `:timeout` - Request timeout in milliseconds

    \"\"\"
    @spec new(keyword()) :: t()
    def new(opts \\\\ []) do
      %__MODULE__{context: Context.build(opts)}
    end

  #{render_resource_accessors(module_name, resources)}
  #{render_ungrouped_endpoints(ungrouped_endpoints)}
  end
  """
end

defp get_unique_resources(endpoints) do
  endpoints
  |> Enum.map(& &1.resource)
  |> Enum.reject(&is_nil/1)
  |> Enum.uniq()
end

defp get_ungrouped_endpoints(endpoints) do
  Enum.filter(endpoints, &is_nil(&1.resource))
end

defp render_resource_accessors(namespace, resources) do
  resources
  |> Enum.map(fn resource ->
    fn_name = String.to_atom(resource)
    module = resource_to_module_name(namespace, resource)

    """
      @doc "Access #{resource} resource endpoints."
      @spec #{fn_name}(t()) :: #{module}.t()
      def #{fn_name}(%__MODULE__{} = client) do
        #{module}.with_client(client)
      end
    """
  end)
  |> Enum.join("\n")
end

defp render_ungrouped_endpoints([]), do: ""
defp render_ungrouped_endpoints(endpoints) do
  Enum.map(endpoints, &render_endpoint_fn/1) |> Enum.join("\n")
end

defp resource_to_module_name(namespace, resource) do
  # Remove ".Client" suffix if present to get base namespace
  base = String.replace_suffix(namespace, ".Client", "")
  module_part = resource
  |> String.split("_")
  |> Enum.map(&String.capitalize/1)
  |> Enum.join()

  "#{base}.#{module_part}"
end
```

---

### Task 3.4: Type Module Generation (2 days)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/codegen/type.ex`
- `/home/home/p/g/n/pristine/test/pristine/codegen/type_test.exs`

**TDD Steps**:

1. **Write Tests**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/codegen/type_test.exs
defmodule Pristine.Codegen.TypeTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen.Type

  describe "render_type_module/3" do
    test "generates module with Sinter schema" do
      type_def = %{
        "fields" => [
          %{"name" => "prompt", "type" => "string", "required" => true},
          %{"name" => "max_tokens", "type" => "integer", "required" => false}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.SampleRequest", "SampleRequest", type_def)

      assert code =~ "defmodule MyAPI.Types.SampleRequest do"
      assert code =~ "@moduledoc"
      assert code =~ "defstruct"
      assert code =~ ":prompt"
      assert code =~ ":max_tokens"
      assert code =~ "def schema do"
      assert code =~ "Sinter.Schema.define"
    end

    test "generates @type t specification" do
      type_def = %{
        "fields" => [
          %{"name" => "name", "type" => "string", "required" => true}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.User", "User", type_def)

      assert code =~ "@type t :: %__MODULE__{"
    end

    test "generates from_map/1 and to_map/1 functions" do
      type_def = %{"fields" => []}

      code = Type.render_type_module("MyAPI.Types.Empty", "Empty", type_def)

      assert code =~ "def from_map(data)"
      assert code =~ "def to_map(%__MODULE__{} = struct)"
    end

    test "generates new/1 constructor" do
      type_def = %{"fields" => []}

      code = Type.render_type_module("MyAPI.Types.Test", "Test", type_def)

      assert code =~ "def new(attrs \\\\ [])"
    end
  end

  describe "render_all_type_modules/2" do
    test "generates module for each type" do
      types = %{
        "SampleRequest" => %{"fields" => []},
        "SampleResponse" => %{"fields" => []}
      }

      modules = Type.render_all_type_modules("MyAPI.Types", types)

      assert Map.has_key?(modules, "MyAPI.Types.SampleRequest")
      assert Map.has_key?(modules, "MyAPI.Types.SampleResponse")
    end
  end
end
```

2. **Implement Type Generator**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/codegen/type.ex
defmodule Pristine.Codegen.Type do
  @moduledoc """
  Generates type modules with Sinter schemas.
  """

  @doc "Renders all type modules."
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

  @doc "Renders a single type module."
  @spec render_type_module(String.t(), String.t(), map()) :: String.t()
  def render_type_module(module_name, type_name, type_def) do
    fields = Map.get(type_def, "fields", [])
    field_names = Enum.map(fields, &Map.get(&1, "name"))
    description = Map.get(type_def, "description", "#{type_name} type.")

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{description}
      \"\"\"

      defstruct #{inspect(Enum.map(field_names, &String.to_atom/1))}

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

  defp render_type_fields(fields) do
    fields
    |> Enum.map(fn field ->
      name = Map.get(field, "name")
      type = map_type_to_typespec(Map.get(field, "type", "any"))
      required = Map.get(field, "required", false)

      type_str = if required, do: type, else: "#{type} | nil"
      "      #{name}: #{type_str}"
    end)
    |> Enum.join(",\n")
  end

  defp render_schema_fields(fields) do
    fields
    |> Enum.map(fn field ->
      name = Map.get(field, "name") |> String.to_atom() |> inspect()
      type = map_type_to_sinter(Map.get(field, "type", "any"))
      required = Map.get(field, "required", false)

      opts = if required, do: "[required: true]", else: "[optional: true]"
      "      {#{name}, #{type}, #{opts}}"
    end)
    |> Enum.join(",\n")
  end

  defp map_type_to_typespec("string"), do: "String.t()"
  defp map_type_to_typespec("integer"), do: "integer()"
  defp map_type_to_typespec("float"), do: "float()"
  defp map_type_to_typespec("number"), do: "number()"
  defp map_type_to_typespec("boolean"), do: "boolean()"
  defp map_type_to_typespec("map"), do: "map()"
  defp map_type_to_typespec("array"), do: "list()"
  defp map_type_to_typespec(_), do: "term()"

  defp map_type_to_sinter("string"), do: ":string"
  defp map_type_to_sinter("integer"), do: ":integer"
  defp map_type_to_sinter("float"), do: ":float"
  defp map_type_to_sinter("number"), do: ":float"
  defp map_type_to_sinter("boolean"), do: ":boolean"
  defp map_type_to_sinter("map"), do: ":map"
  defp map_type_to_sinter("array"), do: "{:array, :any}"
  defp map_type_to_sinter(_), do: ":any"
end
```

---

### Task 3.5: Update Codegen Orchestration (0.5 day)

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/codegen.ex`

Update to generate all module types and write them to the correct paths.

---

## Verification Checklist

```bash
cd /home/home/p/g/n/pristine
mix test
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
```

---

## Expected Outcomes

After Stage 3 completion:

1. **Resource modules** generated per resource group
2. **Client module** with resource accessor functions
3. **Type modules** with Sinter schemas and constructors
4. Generated code matches Tinker SDK ergonomics
5. Full documentation and typespecs
