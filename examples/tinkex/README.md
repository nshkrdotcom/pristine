# Tinkex Example

This directory contains a complete example of generating an API client using Pristine.

## Overview

Tinkex is an Elixir client for the Tinker AI API, generated entirely from the
`manifest.json` file in this directory. This example demonstrates all of Pristine's
key capabilities for SDK generation.

## Files

- `manifest.json` - The Pristine manifest describing the Tinker API
- `generated/` - Generated Elixir code (output of `mix pristine.generate`)

## Generating the Client

```bash
# From the pristine directory
mix pristine.generate \
  --manifest examples/tinkex/manifest.json \
  --output examples/tinkex/generated \
  --namespace Tinkex
```

## Manifest Structure

The manifest defines:

### Resources

| Resource | Description |
|----------|-------------|
| `models` | List and retrieve AI models |
| `sampling` | Create text samples from models |

### Endpoints

| ID | Method | Path | Description |
|----|--------|------|-------------|
| `list_models` | GET | `/models` | List available models |
| `get_model` | GET | `/models/{model_id}` | Get model details |
| `create_sample` | POST | `/samples` | Create a sample |
| `create_sample_stream` | POST | `/samples` | Create streaming sample |
| `get_sample` | GET | `/samples/{sample_id}` | Get sample by ID |
| `create_sample_async` | POST | `/samples/async` | Create async sample |

### Types

The manifest defines 9 types including:

- `Model` - AI model metadata
- `ModelList` - Paginated list of models
- `SampleRequest` - Request parameters
- `SampleResult` - Sample response
- `ContentBlock` - Content blocks (text or tool_use)
- `SampleStreamEvent` - Streaming event types
- `AsyncSampleResponse` - Async operation response
- `Usage` - Token usage information
- `ApiError` - API error details

## Using the Generated Client

```elixir
# Create a context
context = Pristine.Core.Context.new(
  base_url: "https://api.tinker.ai/v1",
  transport: Pristine.Adapters.Transport.Finch,
  serializer: Pristine.Adapters.Serializer.JSON,
  auth: [Pristine.Adapters.Auth.Bearer.new(System.get_env("TINKER_API_KEY"))]
)

# Load the manifest
{:ok, manifest} = Pristine.Manifest.load_file("examples/tinkex/manifest.json")

# List models
{:ok, models} = Pristine.Core.Pipeline.execute(manifest, "list_models", %{}, context)

# Create a sample
request = %{
  "model" => "default-model",
  "prompt" => "Hello, world!",
  "max_tokens" => 100
}
{:ok, result} = Pristine.Core.Pipeline.execute(manifest, "create_sample", request, context)

# Get sample by ID
{:ok, sample} = Pristine.Core.Pipeline.execute(
  manifest,
  "get_sample",
  %{},
  context,
  path_params: %{"sample_id" => result["id"]}
)
```

## Features Demonstrated

### 1. Resource Grouping

Endpoints are grouped into `Models` and `Sampling` modules:

```elixir
# In generated client
client = Tinkex.Client.new(opts)
models_resource = Tinkex.Client.models(client)
sampling_resource = Tinkex.Client.sampling(client)
```

### 2. Type Generation

Full type structs with Sinter schemas:

```elixir
# In generated types
defmodule Tinkex.Types.SampleRequest do
  def schema() do
    Sinter.Schema.define([
      {"model", :string, [required: true]},
      {"prompt", :string, [required: true]},
      {"max_tokens", :integer, [default: 1024]},
      # ...
    ])
  end
end
```

### 3. Streaming Support

SSE streaming with event parsing:

```elixir
{:ok, stream} = Pristine.Core.Pipeline.execute_stream(
  manifest,
  "create_sample_stream",
  request,
  context
)

stream.stream
|> Stream.each(fn event ->
  case event.data do
    %{"type" => "content_block_delta"} = delta ->
      IO.write(delta["delta"]["text"])
    _ -> :ok
  end
end)
|> Stream.run()
```

### 4. Async/Future Operations

Polling-based async operations:

```elixir
{:ok, task} = Pristine.Core.Pipeline.execute_future(
  manifest,
  "create_sample_async",
  request,
  context
)

{:ok, result} = Pristine.Ports.Future.await(task, 30_000)
```

### 5. Idempotency

Request idempotency keys:

```elixir
{:ok, result} = Pristine.Core.Pipeline.execute(
  manifest,
  "create_sample",
  request,
  context,
  idempotency_key: "unique-request-id-123"
)
```

### 6. Error Handling

Typed errors with status codes:

```elixir
case Pristine.Core.Pipeline.execute(manifest, "create_sample", request, context) do
  {:ok, result} ->
    # Success
  {:error, %{status: 429, retry_after: seconds}} ->
    # Rate limited, retry after seconds
  {:error, %{status: 401}} ->
    # Authentication error
  {:error, reason} ->
    # Other error
end
```

## Validation

Validate the manifest:

```bash
mix pristine.validate --manifest examples/tinkex/manifest.json
```

## Documentation Generation

Generate API documentation:

```bash
# Markdown
mix pristine.docs --manifest examples/tinkex/manifest.json --output examples/tinkex/API.md

# HTML
mix pristine.docs --manifest examples/tinkex/manifest.json --format html --output examples/tinkex/API.html
```

## OpenAPI Specification

Generate OpenAPI spec:

```bash
# JSON
mix pristine.openapi --manifest examples/tinkex/manifest.json --output examples/tinkex/openapi.json

# YAML
mix pristine.openapi --manifest examples/tinkex/manifest.json --format yaml --output examples/tinkex/openapi.yaml
```

## Running Tests

```bash
# Run manifest tests
mix test test/examples/tinkex_manifest_test.exs

# Run generation tests
mix test test/examples/tinkex_generation_test.exs

# Run mock server integration tests
mix test test/integration/tinkex_mock_test.exs

# Run live API tests (requires TINKER_API_KEY)
TINKER_API_KEY=your-key mix test test/integration/tinkex_live_test.exs
```

## Customizing

To modify the generated client:

1. Edit `manifest.json` to add/modify endpoints or types
2. Re-run `mix pristine.generate`
3. Generated code in `generated/` will be updated

For custom behavior, you can extend the generated modules or implement
custom adapters using Pristine's port system.
