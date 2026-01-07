# Manifest Reference

Manifests are declarative definitions of your API that drive both code generation and runtime execution. This guide covers the complete manifest format.

## File Formats

Pristine supports three manifest formats:

- **JSON** (`.json`) - Standard JSON format
- **YAML** (`.yaml`, `.yml`) - YAML format
- **Elixir** (`.exs`) - Elixir script returning a map

## Loading Manifests

```elixir
# From file
{:ok, manifest} = Pristine.load_manifest_file("path/to/manifest.json")

# From map
{:ok, manifest} = Pristine.load_manifest(%{
  "name" => "myapi",
  "version" => "1.0.0",
  ...
})
```

## Root Structure

```json
{
  "name": "string (required)",
  "version": "string (required)",
  "base_url": "string (optional)",
  "endpoints": "[array] (required)",
  "types": "{object} (required)",
  "auth": "{object} (optional)",
  "defaults": "{object} (optional)",
  "retry_policies": "{object} (optional)",
  "rate_limits": "{object} (optional)",
  "error_types": "{object} (optional)",
  "policies": "{object} (optional)"
}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | SDK/API name (used in generated module names) |
| `version` | string | Semantic version (e.g., "1.0.0") |
| `endpoints` | array | List of endpoint definitions |
| `types` | object | Type definitions for requests/responses |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `base_url` | string | Default base URL for all endpoints |
| `auth` | object | Default authentication configuration |
| `defaults` | object | Default values (timeout, headers, etc.) |
| `retry_policies` | object | Named retry policy definitions |
| `rate_limits` | object | Named rate limit configurations |
| `error_types` | object | Error type mappings by status code |
| `policies` | object | Generic policy definitions |

## Endpoints

Each endpoint defines an API operation:

```json
{
  "endpoints": [
    {
      "id": "create_user",
      "method": "POST",
      "path": "/users",
      "resource": "users",
      "request": "CreateUserRequest",
      "response": "User",
      "description": "Create a new user"
    }
  ]
}
```

### Required Endpoint Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique endpoint identifier |
| `method` | string | HTTP method (GET, POST, PUT, DELETE, PATCH) |
| `path` | string | URL path (must start with `/`) |

### Optional Endpoint Fields

#### Core

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Human-readable description |
| `resource` | string | Resource group name |
| `request` | string | Request type name (references `types`) |
| `response` | string | Response type name |

#### Headers and Body

| Field | Type | Description |
|-------|------|-------------|
| `headers` | object | Default headers for this endpoint |
| `query` | object | Default query parameters |
| `content_type` | string | Content-Type header value |
| `body_type` | string | Body encoding: `"json"`, `"multipart"`, `"raw"` |

#### Authentication

| Field | Type | Description |
|-------|------|-------------|
| `auth` | object | Override authentication for this endpoint |

#### Resilience

| Field | Type | Description |
|-------|------|-------------|
| `timeout` | integer | Request timeout in milliseconds |
| `retry` | string | Name of retry policy to apply |
| `circuit_breaker` | string | Circuit breaker configuration name |
| `rate_limit` | string | Rate limit configuration name |
| `idempotency` | boolean | Mark endpoint as idempotent |
| `idempotency_header` | string | Header name for idempotency key |

#### Async and Streaming

| Field | Type | Description |
|-------|------|-------------|
| `async` | boolean | Enable async/future pattern |
| `poll_endpoint` | string | Endpoint ID for polling async results |
| `streaming` | boolean | Enable streaming response |
| `stream_format` | string | Stream format (e.g., `"sse"`) |
| `event_types` | array | List of expected event type names |

#### Error Handling

| Field | Type | Description |
|-------|------|-------------|
| `error_types` | array | List of error type names |
| `response_unwrap` | string | JSONPath to unwrap response |

#### Metadata

| Field | Type | Description |
|-------|------|-------------|
| `deprecated` | boolean | Mark endpoint as deprecated |
| `tags` | array | String tags for categorization |
| `telemetry` | string | Custom telemetry event name |

### Path Parameters

Use `{param}` or `:param` syntax:

```json
{
  "id": "get_user",
  "path": "/users/{user_id}",
  "method": "GET"
}
```

Generated code:
```elixir
def get(resource, user_id, opts \\ []) do
  opts = merge_path_params(opts, %{"user_id" => user_id})
  ...
end
```

## Types

Types define the structure of requests and responses:

```json
{
  "types": {
    "User": {
      "fields": {
        "id": {"type": "string", "required": true},
        "name": {"type": "string", "required": true},
        "email": {"type": "string"},
        "age": {"type": "integer", "gt": 0}
      }
    }
  }
}
```

### Type Categories

#### Object Types (Default)

```json
{
  "User": {
    "fields": {
      "id": {"type": "string", "required": true},
      "name": {"type": "string", "required": true}
    }
  }
}
```

#### Union Types (Discriminated)

```json
{
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
```

Generated code handles variant dispatch:
```elixir
def decode(data) do
  case data["type"] do
    "success" -> SuccessResult.decode(data)
    "error" -> ErrorResult.decode(data)
    other -> {:error, {:unknown_variant, other}}
  end
end
```

#### Alias Types

Simple type aliases or enums:

```json
{
  "Status": {
    "type": "string",
    "choices": ["pending", "active", "completed"]
  }
}
```

### Field Properties

#### Basic Types

| Type | Description | Elixir Type |
|------|-------------|-------------|
| `string` | Text | `String.t()` |
| `integer` | Whole number | `integer()` |
| `number` | Float/decimal | `number()` |
| `boolean` | True/false | `boolean()` |
| `object` | Nested object | `map()` |
| `array` | List | `list()` |

#### Type References

Reference another type:

```json
{
  "profile": {"type_ref": "UserProfile"}
}
```

Alternative syntax:
```json
{
  "profile": {"$ref": "UserProfile"}
}
```

#### Arrays

```json
{
  "tags": {
    "type": "array",
    "items": {"type": "string"}
  }
}
```

Array of type references:
```json
{
  "users": {
    "type": "array",
    "items": {"type_ref": "User"}
  }
}
```

#### Validation Constraints

| Constraint | Applies To | Description |
|------------|------------|-------------|
| `required` | any | Field must be present |
| `optional` | any | Field is optional |
| `default` | any | Default value |
| `min_length` | string | Minimum length |
| `max_length` | string | Maximum length |
| `min_items` | array | Minimum array length |
| `max_items` | array | Maximum array length |
| `gt` | number | Greater than |
| `gteq` | number | Greater than or equal |
| `lt` | number | Less than |
| `lteq` | number | Less than or equal |
| `format` | string | Format validator (email, date, etc.) |
| `choices` | string | Enum values |

#### Field Options

| Option | Description |
|--------|-------------|
| `alias` | JSON key name (if different from field name) |
| `omit_if` | Condition to omit field from output |
| `description` | Field documentation |

### Complete Type Example

```json
{
  "CreateUserRequest": {
    "fields": {
      "name": {
        "type": "string",
        "required": true,
        "min_length": 1,
        "max_length": 100,
        "description": "User's full name"
      },
      "email": {
        "type": "string",
        "required": true,
        "format": "email"
      },
      "age": {
        "type": "integer",
        "gteq": 0,
        "lteq": 150
      },
      "tags": {
        "type": "array",
        "items": {"type": "string"},
        "max_items": 10
      },
      "profile": {
        "type_ref": "UserProfile"
      },
      "role": {
        "type": "string",
        "choices": ["admin", "user", "guest"],
        "default": "user"
      }
    }
  }
}
```

## Authentication

Configure default authentication:

```json
{
  "auth": {
    "type": "bearer",
    "env_var": "API_TOKEN"
  }
}
```

### Auth Types

#### Bearer Token

```json
{
  "auth": {
    "type": "bearer",
    "env_var": "API_TOKEN",
    "prefix": "Bearer"
  }
}
```

#### API Key

```json
{
  "auth": {
    "type": "api_key",
    "header": "X-API-Key",
    "env_var": "API_KEY"
  }
}
```

## Retry Policies

Define named retry policies:

```json
{
  "retry_policies": {
    "default": {
      "max_attempts": 3,
      "backoff": "exponential",
      "base_delay_ms": 1000,
      "max_delay_ms": 30000
    },
    "aggressive": {
      "max_attempts": 5,
      "backoff": "linear",
      "base_delay_ms": 500
    },
    "none": {
      "max_attempts": 1
    }
  }
}
```

### Policy Options

| Field | Type | Description |
|-------|------|-------------|
| `max_attempts` | integer | Maximum retry attempts |
| `backoff` | string | Backoff strategy: `"exponential"`, `"linear"`, `"constant"` |
| `base_delay_ms` | integer | Initial delay in milliseconds |
| `max_delay_ms` | integer | Maximum delay cap |
| `jitter` | boolean | Add randomization to delays |

Reference in endpoints:
```json
{
  "id": "important_call",
  "retry": "aggressive"
}
```

## Rate Limits

Define named rate limit configurations:

```json
{
  "rate_limits": {
    "standard": {
      "limit": 100,
      "window": 60
    },
    "burst": {
      "limit": 10,
      "window": 1
    }
  }
}
```

## Error Types

Map HTTP status codes to error types:

```json
{
  "error_types": {
    "400": {
      "name": "BadRequestError",
      "retryable": false
    },
    "401": {
      "name": "AuthenticationError",
      "retryable": false
    },
    "429": {
      "name": "RateLimitError",
      "retryable": true
    },
    "5xx": {
      "name": "ServerError",
      "retryable": true
    }
  }
}
```

## Defaults

Set default values:

```json
{
  "defaults": {
    "timeout": 30000,
    "headers": {
      "User-Agent": "MySDK/1.0.0"
    },
    "retry": "default"
  }
}
```

## Complete Example

```json
{
  "name": "petstore",
  "version": "1.0.0",
  "base_url": "https://api.petstore.example.com",

  "auth": {
    "type": "bearer",
    "env_var": "PETSTORE_API_TOKEN"
  },

  "defaults": {
    "timeout": 30000,
    "retry": "default"
  },

  "retry_policies": {
    "default": {
      "max_attempts": 3,
      "backoff": "exponential",
      "base_delay_ms": 1000
    }
  },

  "error_types": {
    "404": {"name": "NotFoundError", "retryable": false},
    "429": {"name": "RateLimitError", "retryable": true},
    "5xx": {"name": "ServerError", "retryable": true}
  },

  "endpoints": [
    {
      "id": "list_pets",
      "method": "GET",
      "path": "/pets",
      "resource": "pets",
      "response": "PetList",
      "description": "List all pets"
    },
    {
      "id": "get_pet",
      "method": "GET",
      "path": "/pets/{pet_id}",
      "resource": "pets",
      "response": "Pet",
      "description": "Get a pet by ID"
    },
    {
      "id": "create_pet",
      "method": "POST",
      "path": "/pets",
      "resource": "pets",
      "request": "CreatePetRequest",
      "response": "Pet",
      "description": "Create a new pet"
    }
  ],

  "types": {
    "Pet": {
      "fields": {
        "id": {"type": "string", "required": true},
        "name": {"type": "string", "required": true},
        "species": {
          "type": "string",
          "choices": ["dog", "cat", "bird", "fish"]
        },
        "age": {"type": "integer", "gteq": 0}
      }
    },
    "PetList": {
      "fields": {
        "data": {
          "type": "array",
          "items": {"type_ref": "Pet"},
          "required": true
        },
        "has_more": {"type": "boolean", "required": true}
      }
    },
    "CreatePetRequest": {
      "fields": {
        "name": {"type": "string", "required": true, "min_length": 1},
        "species": {"type": "string", "required": true},
        "age": {"type": "integer"}
      }
    }
  }
}
```

## Validation

Manifests are validated on load:

```elixir
case Pristine.load_manifest_file("manifest.json") do
  {:ok, manifest} ->
    # Valid manifest

  {:error, errors} ->
    # List of validation errors
    Enum.each(errors, &IO.puts/1)
end
```

Common validation errors:
- `"name is required"`
- `"version is required"`
- `"endpoints are required"`
- `"endpoint {id} must include method and path"`
- `"endpoint {id} path must start with '/'"`
