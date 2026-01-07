# Code Generation

Pristine generates type-safe Elixir SDK code from manifest definitions. This guide covers the code generation system and customization options.

## Overview

The code generation pipeline transforms manifests into three types of modules:

```
Manifest
    │
    ├─► Type Modules (lib/types/*.ex)
    │   - Structs with validation schemas
    │   - encode/decode functions
    │
    ├─► Resource Modules (lib/resources/*.ex)
    │   - Endpoint functions grouped by resource
    │   - Parameter handling
    │
    └─► Client Module (lib/client.ex)
        - Main entry point
        - Resource accessors
        - Embedded manifest
```

## Running Code Generation

### Mix Task

```bash
mix pristine.generate \
  --manifest path/to/manifest.json \
  --output lib/myapi \
  --namespace MyAPI
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--manifest` | Path to manifest file | Required |
| `--output` | Output directory | `lib/generated` |
| `--namespace` | Module namespace | Derived from manifest name |

### Programmatic

```elixir
{:ok, manifest} = Pristine.load_manifest_file("manifest.json")

{:ok, sources} = Pristine.Codegen.build_sources(manifest,
  namespace: "MyAPI",
  output_dir: "lib/myapi"
)

:ok = Pristine.Codegen.write_sources(sources)
```

## Generated Modules

### Type Modules

For each type in your manifest, a type module is generated:

**Manifest:**
```json
{
  "types": {
    "User": {
      "fields": {
        "id": {"type": "string", "required": true},
        "name": {"type": "string", "required": true},
        "email": {"type": "string"}
      }
    }
  }
}
```

**Generated (`lib/myapi/types/user.ex`):**
```elixir
defmodule MyAPI.Types.User do
  @moduledoc "User type."

  defstruct [:id, :name, :email]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    email: String.t() | nil
  }

  @doc "Sinter validation schema."
  def schema do
    Sinter.Schema.define([
      {:id, :string, [required: true]},
      {:name, :string, [required: true]},
      {:email, :string, []}
    ])
  end

  @doc "Decode from map with validation."
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok, %__MODULE__{
        id: validated["id"],
        name: validated["name"],
        email: validated["email"]
      }}
    end
  end

  @doc "Encode to map."
  def encode(%__MODULE__{} = struct) do
    %{
      "id" => struct.id,
      "name" => struct.name,
      "email" => struct.email
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create from map (without validation)."
  def from_map(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      name: data["name"],
      email: data["email"]
    }
  end

  @doc "Create new instance."
  def new(attrs \\ []) do
    struct(__MODULE__, attrs)
  end

  @doc "Convert to map."
  def to_map(%__MODULE__{} = struct) do
    encode(struct)
  end
end
```

### Union Types

**Manifest:**
```json
{
  "types": {
    "Result": {
      "kind": "union",
      "discriminator": {
        "field": "type",
        "mapping": {
          "success": "SuccessResult",
          "error": "ErrorResult"
        }
      }
    }
  }
}
```

**Generated:**
```elixir
defmodule MyAPI.Types.Result do
  @moduledoc "Result union type."

  alias MyAPI.Types.{SuccessResult, ErrorResult}

  @type t :: SuccessResult.t() | ErrorResult.t()

  def schema do
    {:discriminated_union,
     discriminator: "type",
     variants: %{
       "success" => SuccessResult.schema(),
       "error" => ErrorResult.schema()
     }}
  end

  def decode(data) when is_map(data) do
    case data["type"] do
      "success" -> SuccessResult.decode(data)
      "error" -> ErrorResult.decode(data)
      other -> {:error, {:unknown_variant, other}}
    end
  end
end
```

### Resource Modules

Endpoints are grouped by `resource` field:

**Manifest:**
```json
{
  "endpoints": [
    {
      "id": "list_users",
      "method": "GET",
      "path": "/users",
      "resource": "users",
      "response": "UserList"
    },
    {
      "id": "get_user",
      "method": "GET",
      "path": "/users/{id}",
      "resource": "users",
      "response": "User"
    },
    {
      "id": "create_user",
      "method": "POST",
      "path": "/users",
      "resource": "users",
      "request": "CreateUserRequest",
      "response": "User"
    }
  ]
}
```

**Generated (`lib/myapi/resources/users.ex`):**
```elixir
defmodule MyAPI.Users do
  @moduledoc "Users resource endpoints."

  defstruct [:context]

  @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

  @doc "Create resource from client."
  def with_client(%{context: context}) do
    %__MODULE__{context: context}
  end

  @doc """
  List all users.

  ## Parameters
    * `opts` - Optional parameters:
      * `:timeout` - Request timeout in milliseconds

  ## Returns
    * `{:ok, response}` on success
    * `{:error, Pristine.Error.t()}` on failure
  """
  @spec list(%__MODULE__{}, keyword()) ::
    {:ok, term()} | {:error, Pristine.Error.t()}
  def list(%__MODULE__{context: context}, opts \\ []) do
    Pristine.Runtime.execute(
      MyAPI.Client.manifest(),
      :list_users,
      %{},
      context,
      opts
    )
  end

  @doc """
  Get a user by ID.

  ## Parameters
    * `id` - User ID (path parameter)
    * `opts` - Optional parameters
  """
  @spec get(%__MODULE__{}, String.t(), keyword()) ::
    {:ok, term()} | {:error, Pristine.Error.t()}
  def get(%__MODULE__{context: context}, id, opts \\ []) do
    opts = merge_path_params(opts, %{"id" => id})

    Pristine.Runtime.execute(
      MyAPI.Client.manifest(),
      :get_user,
      %{},
      context,
      opts
    )
  end

  @doc """
  Create a new user.

  ## Parameters
    * `name` - User name (required)
    * `opts` - Optional parameters:
      * `:email` - User email
  """
  @spec create(%__MODULE__{}, String.t(), keyword()) ::
    {:ok, term()} | {:error, Pristine.Error.t()}
  def create(%__MODULE__{context: context}, name, opts \\ []) do
    payload = %{"name" => name}
    |> maybe_put("email", Keyword.get(opts, :email))

    Pristine.Runtime.execute(
      MyAPI.Client.manifest(),
      :create_user,
      payload,
      context,
      Keyword.drop(opts, [:email])
    )
  end

  # Helper functions (generated as needed)

  defp merge_path_params(opts, path_params) do
    existing = Keyword.get(opts, :path_params, %{})
    Keyword.put(opts, :path_params, Map.merge(existing, path_params))
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, _key, Sinter.NotGiven), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
```

### Client Module

**Generated (`lib/myapi/client.ex`):**
```elixir
defmodule MyAPI.Client do
  @moduledoc """
  Generated API client for MyAPI v1.0.0.

  This module was generated by Pristine from a manifest definition.
  """

  alias Pristine.Core.Context

  defstruct [:context]

  @type t :: %__MODULE__{context: Context.t()}

  # Embedded manifest for runtime access
  @manifest %{
    name: "myapi",
    version: "1.0.0",
    # ... full manifest
  }

  @doc "Returns the embedded manifest."
  @spec manifest() :: map()
  def manifest, do: @manifest

  @doc """
  Create a new client instance.

  ## Options
    * `:base_url` - Override the default base URL
    * `:headers` - Additional headers to include
    * `:auth` - Authentication configuration
    * `:transport` - Transport adapter module
    * `:timeout` - Request timeout in milliseconds

  ## Examples

      client = MyAPI.Client.new(
        base_url: "https://api.example.com",
        auth: [{Pristine.Adapters.Auth.Bearer, token: "..."}]
      )
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{context: Context.new(opts)}
  end

  @doc "Access users resource endpoints."
  @spec users(t()) :: MyAPI.Users.t()
  def users(%__MODULE__{} = client) do
    MyAPI.Users.with_client(client)
  end

  @doc """
  Execute any endpoint by ID.

  For advanced use cases where you need direct endpoint access.
  """
  @spec execute(String.t() | atom(), map(), keyword()) ::
    {:ok, term()} | {:error, term()}
  def execute(%__MODULE__{context: context}, endpoint_id, payload, opts \\ []) do
    Pristine.Runtime.execute(@manifest, endpoint_id, payload, context, opts)
  end
end
```

## Async and Streaming Endpoints

### Async Endpoints

For endpoints with `async: true`:

**Manifest:**
```json
{
  "id": "generate_report",
  "async": true,
  "poll_endpoint": "get_report_status"
}
```

**Generated (additional function):**
```elixir
@doc "Generate report (async)."
@spec generate_report_async(%__MODULE__{}, map(), keyword()) ::
  {:ok, Task.t()} | {:error, term()}
def generate_report_async(%__MODULE__{context: context}, payload, opts \\ []) do
  Pristine.Core.Pipeline.execute_future(
    MyAPI.Client.manifest(),
    :generate_report,
    payload,
    context,
    opts
  )
end
```

### Streaming Endpoints

For endpoints with `streaming: true`:

**Manifest:**
```json
{
  "id": "stream_events",
  "streaming": true,
  "stream_format": "sse"
}
```

**Generated (additional function):**
```elixir
@doc "Stream events (SSE)."
@spec stream_events_stream(%__MODULE__{}, map(), keyword()) ::
  {:ok, Pristine.Core.StreamResponse.t()} | {:error, term()}
def stream_events_stream(%__MODULE__{context: context}, payload, opts \\ []) do
  Pristine.Core.Pipeline.execute_stream(
    MyAPI.Client.manifest(),
    :stream_events,
    payload,
    context,
    opts
  )
end
```

## Function Signatures

The generator analyzes request types to create ergonomic function signatures:

### Required Parameters

Required fields become positional arguments:

```json
{
  "CreateUserRequest": {
    "fields": {
      "name": {"type": "string", "required": true},
      "email": {"type": "string", "required": true}
    }
  }
}
```

```elixir
def create(resource, name, email, opts \\ [])
```

### Optional Parameters

Optional fields go in the `opts` keyword list:

```json
{
  "CreateUserRequest": {
    "fields": {
      "name": {"type": "string", "required": true},
      "bio": {"type": "string"},
      "age": {"type": "integer"}
    }
  }
}
```

```elixir
def create(resource, name, opts \\ [])
# opts can include: :bio, :age
```

### Path Parameters

Path parameters are extracted from the path pattern:

```json
{
  "path": "/users/{user_id}/posts/{post_id}"
}
```

```elixir
def get(resource, user_id, post_id, opts \\ [])
```

### Literal Fields

Fields with `type: "literal"` are not parameters:

```json
{
  "kind": {"type": "literal", "value": "user"}
}
```

The literal value is automatically included in the payload.

## Type Reference Handling

When types reference other types:

```json
{
  "User": {
    "fields": {
      "profile": {"type_ref": "UserProfile"}
    }
  }
}
```

Generated code includes encoding helpers:

```elixir
def encode(%__MODULE__{} = struct) do
  %{
    "profile" => encode_ref(struct.profile, MyAPI.Types.UserProfile)
  }
end

defp encode_ref(nil, _module), do: nil
defp encode_ref(value, module) do
  if function_exported?(module, :encode, 1) do
    module.encode(value)
  else
    value
  end
end
```

## Customization

### Namespace

Control the module namespace:

```bash
mix pristine.generate --namespace MyApp.API.V1
```

Generates:
- `MyApp.API.V1.Client`
- `MyApp.API.V1.Types.User`
- `MyApp.API.V1.Users`

### Output Structure

Default structure:
```
lib/myapi/
├── client.ex
├── types/
│   ├── user.ex
│   └── user_list.ex
└── resources/
    └── users.ex
```

### Documentation

Generated modules include `@moduledoc` and `@doc` annotations derived from manifest descriptions.

## Validation at Generation Time

The codegen validates:

1. **Manifest structure** - Required fields present
2. **Type references** - Referenced types exist
3. **Endpoint consistency** - Request/response types exist
4. **Path parameters** - Path params have corresponding type fields

Errors are reported before any files are written.

## Regeneration

When your API changes:

1. Update the manifest
2. Re-run code generation
3. Generated code is completely replaced

**Best Practice:** Don't manually edit generated files. If you need customization, create wrapper modules.

## Integration with Runtime

Generated code uses `Pristine.Runtime.execute/5` which:

1. Loads the embedded manifest
2. Resolves the endpoint
3. Executes through the pipeline
4. Returns validated results

This means generated SDKs have full access to:
- Retry policies
- Circuit breakers
- Rate limiting
- Telemetry
- All other Pristine features
