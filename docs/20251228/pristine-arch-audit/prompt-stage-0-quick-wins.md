# Stage 0: Quick Wins Implementation Prompt

**Estimated Effort**: 3-5 days
**Prerequisites**: None
**Goal**: All tests pass, no warnings, no errors, no dialyzer errors, no `mix credo --strict` errors

---

## Context

You are implementing Stage 0 of the Pristine architecture buildout. This stage focuses on quick wins that provide immediate value with minimal risk. You will be working across multiple repositories that are linked via local path dependencies.

### Project Overview

Pristine is a hexagonal manifest-driven SDK generator for Elixir. The goal is to enable generation of complete API clients (like Tinkex) from declarative manifests plus pluggable adapters.

### Repository Locations

| Repository | Path | Purpose |
|------------|------|---------|
| Pristine | `/home/home/p/g/n/pristine` | Main SDK generator |
| Sinter | `/home/home/p/g/n/sinter` | Schema validation library |
| Foundation | `/home/home/p/g/n/foundation` | Resilience (retry, circuit breaker) |
| MultipartEx | `/home/home/p/g/n/multipart_ex` | Multipart encoding |

---

## Required Reading

Before starting, read these files to understand the current architecture:

### Architecture Documentation
```
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/overview.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/gap-analysis.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/roadmap.md
```

### Pristine Source Files
```
/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex
/home/home/p/g/n/pristine/lib/pristine/codegen.ex
/home/home/p/g/n/pristine/lib/pristine/manifest.ex
/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex
/home/home/p/g/n/pristine/lib/pristine/manifest/schema.ex
/home/home/p/g/n/pristine/lib/pristine/core/context.ex
/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex
/home/home/p/g/n/pristine/mix.exs
```

### Sinter Source Files
```
/home/home/p/g/n/sinter/lib/sinter/types.ex
/home/home/p/g/n/sinter/lib/sinter/json_schema.ex
/home/home/p/g/n/sinter/lib/sinter/schema.ex
```

### Existing Mix Task
```
/home/home/p/g/n/pristine/lib/mix/tasks/pristine.generate.ex
```

---

## Tasks

### Task 0.1: Add Dialyzer and Credo Dependencies

**Gap Addressed**: GAP-026, GAP-027

**Files to Modify**:
- `/home/home/p/g/n/pristine/mix.exs`

**Files to Create**:
- `/home/home/p/g/n/pristine/.credo.exs`

**Instructions**:

1. Add dependencies to `mix.exs`:
```elixir
defp deps do
  [
    # ... existing deps ...
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
  ]
end
```

2. Create `.credo.exs` with strict configuration:
```elixir
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: %{
        enabled: [
          {Credo.Check.Consistency.TabsOrSpaces, []},
          {Credo.Check.Design.AliasUsage, [priority: :low, if_nested_deeper_than: 2]},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Warning.IoInspect, []}
        ]
      }
    }
  ]
}
```

3. Run `mix deps.get`

4. Run `mix dialyzer --plt` to build PLT (first time only)

5. Verify: `mix credo --strict` passes with no issues

6. Verify: `mix dialyzer` passes with no errors

---

### Task 0.2: Codegen Documentation Enhancement

**Gap Addressed**: GAP-008, GAP-010

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex`

**Files to Create**:
- `/home/home/p/g/n/pristine/test/pristine/codegen/elixir_test.exs`

**TDD Steps**:

1. **Write Tests First**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/codegen/elixir_test.exs
defmodule Pristine.Codegen.ElixirTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen.Elixir, as: ElixirCodegen
  alias Pristine.Manifest.Endpoint

  describe "render_endpoint_fn/1" do
    test "generates @doc from endpoint description" do
      endpoint = %Endpoint{
        id: :create_model,
        method: :post,
        path: "/api/v1/create_model",
        description: "Creates a new model.\n\nPass a LoRA config to create a new LoRA adapter."
      }

      code = ElixirCodegen.render_endpoint_fn(endpoint)

      assert code =~ ~s(@doc """)
      assert code =~ "Creates a new model."
      assert code =~ "Pass a LoRA config"
    end

    test "generates @spec with request and response types" do
      endpoint = %Endpoint{
        id: :create_model,
        method: :post,
        path: "/api/v1/create_model",
        request: "CreateModelRequest",
        response: "UntypedAPIFuture"
      }

      code = ElixirCodegen.render_endpoint_fn(endpoint)

      assert code =~ "@spec create_model(map(), Pristine.Core.Context.t(), keyword())"
      assert code =~ ":: {:ok, term()} | {:error, term()}"
    end

    test "handles nil description gracefully" do
      endpoint = %Endpoint{
        id: :test,
        method: :get,
        path: "/test",
        description: nil
      }

      code = ElixirCodegen.render_endpoint_fn(endpoint)

      # Should not crash, should generate valid code
      refute code =~ "@doc nil"
    end

    test "handles empty description" do
      endpoint = %Endpoint{
        id: :test,
        method: :get,
        path: "/test",
        description: ""
      }

      code = ElixirCodegen.render_endpoint_fn(endpoint)

      # Should not generate empty @doc
      refute code =~ ~s(@doc "")
    end
  end

  describe "render_client_module/2" do
    test "generates module with @moduledoc" do
      manifest = %Pristine.Manifest{
        name: "TestAPI",
        version: "1.0.0",
        endpoints: [],
        types: %{}
      }

      code = ElixirCodegen.render_client_module("TestAPI.Client", manifest)

      assert code =~ "defmodule TestAPI.Client do"
      assert code =~ "@moduledoc"
    end
  end
end
```

2. **Run Tests** (they should fail initially):
```bash
cd /home/home/p/g/n/pristine && mix test test/pristine/codegen/elixir_test.exs
```

3. **Implement Changes**:

Update `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex`:

```elixir
defmodule Pristine.Codegen.Elixir do
  @moduledoc """
  Elixir code generator for Pristine manifests.
  """

  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint

  @doc """
  Renders a complete client module from a manifest.
  """
  @spec render_client_module(String.t(), Manifest.t()) :: String.t()
  def render_client_module(module_name, %Manifest{} = manifest) do
    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      Generated API client for #{manifest.name} v#{manifest.version}.

      This module was generated by Pristine from a manifest definition.
      \"\"\"

      @manifest #{inspect(manifest, pretty: true, limit: :infinity)}

      @doc "Returns the manifest used to generate this module."
      @spec manifest() :: Pristine.Manifest.t()
      def manifest, do: @manifest

    #{render_endpoints(manifest)}

      @doc "Execute an endpoint by ID."
      @spec execute(atom(), map(), Pristine.Core.Context.t(), keyword()) ::
              {:ok, term()} | {:error, term()}
      def execute(endpoint_id, payload, context, opts \\\\ []) do
        Pristine.Runtime.execute(@manifest, endpoint_id, payload, context, opts)
      end
    end
    """
  end

  @doc """
  Renders a single endpoint function.
  """
  @spec render_endpoint_fn(Endpoint.t()) :: String.t()
  def render_endpoint_fn(%Endpoint{} = endpoint) do
    fn_name = endpoint_to_fn_name(endpoint.id)
    doc = render_doc(endpoint)
    spec = render_spec(fn_name, endpoint)

    """
    #{doc}#{spec}  def #{fn_name}(payload, context, opts \\\\ []) do
        Pristine.Runtime.execute(@manifest, #{inspect(endpoint.id)}, payload, context, opts)
      end
    """
  end

  # Private functions

  defp render_endpoints(%Manifest{endpoints: endpoints}) do
    endpoints
    |> Enum.map(&render_endpoint_fn/1)
    |> Enum.join("\n")
  end

  defp render_doc(%Endpoint{description: nil}), do: ""
  defp render_doc(%Endpoint{description: ""}), do: ""

  defp render_doc(%Endpoint{description: desc, request: req, response: resp}) do
    params_doc = render_params_doc(req)
    returns_doc = render_returns_doc(resp)

    """
      @doc \"\"\"
      #{String.trim(desc)}

    #{params_doc}#{returns_doc}  \"\"\"
    """
  end

  defp render_params_doc(nil), do: ""

  defp render_params_doc(request_type) do
    """
      ## Parameters

        * `payload` - #{request_type} map
        * `context` - Pristine.Core.Context runtime context
        * `opts` - Request options (timeout, headers, etc.)

    """
  end

  defp render_returns_doc(nil), do: ""

  defp render_returns_doc(response_type) do
    """
      ## Returns

        * `{:ok, #{response_type}}` on success
        * `{:error, term()}` on failure

    """
  end

  defp render_spec(fn_name, %Endpoint{}) do
    """
      @spec #{fn_name}(map(), Pristine.Core.Context.t(), keyword()) ::
              {:ok, term()} | {:error, term()}
    """
  end

  defp endpoint_to_fn_name(id) when is_atom(id), do: id
  defp endpoint_to_fn_name(id) when is_binary(id), do: String.to_atom(id)
end
```

4. **Run Tests Again**:
```bash
cd /home/home/p/g/n/pristine && mix test test/pristine/codegen/elixir_test.exs
```

5. **Verify No Warnings**:
```bash
cd /home/home/p/g/n/pristine && mix compile --warnings-as-errors
```

6. **Verify Credo**:
```bash
cd /home/home/p/g/n/pristine && mix credo --strict
```

7. **Verify Dialyzer**:
```bash
cd /home/home/p/g/n/pristine && mix dialyzer
```

---

### Task 0.3: Literal Type in Sinter

**Gap Addressed**: GAP-015

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/types.ex`
- `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`

**Files to Create/Modify**:
- `/home/home/p/g/n/sinter/test/sinter/types_test.exs` (add tests)

**TDD Steps**:

1. **Write Tests First**:

```elixir
# Add to /home/home/p/g/n/sinter/test/sinter/types_test.exs

describe "literal type" do
  test "validates exact string match" do
    assert {:ok, "sample"} = Sinter.Types.validate({:literal, "sample"}, "sample", [])
  end

  test "rejects non-matching string" do
    assert {:error, _} = Sinter.Types.validate({:literal, "sample"}, "other", [])
  end

  test "validates exact atom match" do
    assert {:ok, :foo} = Sinter.Types.validate({:literal, :foo}, :foo, [])
  end

  test "validates exact integer match" do
    assert {:ok, 42} = Sinter.Types.validate({:literal, 42}, 42, [])
  end

  test "rejects type mismatch even with same representation" do
    assert {:error, _} = Sinter.Types.validate({:literal, "42"}, 42, [])
  end

  test "returns meaningful error message" do
    {:error, error} = Sinter.Types.validate({:literal, "expected"}, "actual", [])
    assert error.message =~ "expected" or error.code == :literal_mismatch
  end
end
```

2. **Write JSON Schema Test**:

```elixir
# Add to /home/home/p/g/n/sinter/test/sinter/json_schema_test.exs

describe "literal type" do
  test "generates const for literal string" do
    schema = Sinter.JsonSchema.type_to_json_schema({:literal, "sample"})
    assert schema == %{"const" => "sample"}
  end

  test "generates const for literal integer" do
    schema = Sinter.JsonSchema.type_to_json_schema({:literal, 42})
    assert schema == %{"const" => 42}
  end

  test "generates const for literal boolean" do
    schema = Sinter.JsonSchema.type_to_json_schema({:literal, true})
    assert schema == %{"const" => true}
  end
end
```

3. **Implement in types.ex**:

Add to `/home/home/p/g/n/sinter/lib/sinter/types.ex`:

```elixir
# Add to @type type_spec union
# {:literal, term()}

# Add validation clause
def validate({:literal, expected}, value, _opts) when value === expected do
  {:ok, value}
end

def validate({:literal, expected}, value, opts) do
  path = Keyword.get(opts, :path, [])
  error = %Sinter.Error{
    path: path,
    code: :literal_mismatch,
    message: "expected literal #{inspect(expected)}, got #{inspect(value)}",
    context: %{expected: expected, actual: value}
  }
  {:error, error}
end
```

4. **Implement in json_schema.ex**:

Add to `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`:

```elixir
def type_to_json_schema({:literal, value}) do
  %{"const" => value}
end
```

5. **Run All Tests**:
```bash
cd /home/home/p/g/n/sinter && mix test
```

6. **Verify Compilation**:
```bash
cd /home/home/p/g/n/sinter && mix compile --warnings-as-errors
```

---

### Task 0.4: Validation Mix Task

**Gap Addressed**: GAP-013

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.validate.ex`
- `/home/home/p/g/n/pristine/test/mix/tasks/pristine.validate_test.exs`

**TDD Steps**:

1. **Create Test Fixtures**:

```bash
mkdir -p /home/home/p/g/n/pristine/test/fixtures
```

Create `/home/home/p/g/n/pristine/test/fixtures/valid_manifest.json`:
```json
{
  "name": "TestAPI",
  "version": "1.0.0",
  "endpoints": [
    {
      "id": "test",
      "method": "GET",
      "path": "/test"
    }
  ],
  "types": {}
}
```

Create `/home/home/p/g/n/pristine/test/fixtures/invalid_manifest.json`:
```json
{
  "name": "TestAPI"
}
```

2. **Write Tests First**:

```elixir
# /home/home/p/g/n/pristine/test/mix/tasks/pristine.validate_test.exs
defmodule Mix.Tasks.Pristine.ValidateTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @valid_fixture "test/fixtures/valid_manifest.json"
  @invalid_fixture "test/fixtures/invalid_manifest.json"

  describe "run/1" do
    test "validates a correct manifest file" do
      output = capture_io(fn ->
        Mix.Tasks.Pristine.Validate.run(["--manifest", @valid_fixture])
      end)

      assert output =~ "valid" or output =~ "Valid"
    end

    test "reports errors for invalid manifest" do
      output = capture_io(fn ->
        try do
          Mix.Tasks.Pristine.Validate.run(["--manifest", @invalid_fixture])
        catch
          :exit, _ -> :ok
        end
      end)

      assert output =~ "error" or output =~ "Error" or output =~ "required"
    end

    test "handles missing manifest file" do
      output = capture_io(fn ->
        try do
          Mix.Tasks.Pristine.Validate.run(["--manifest", "nonexistent.json"])
        catch
          :exit, _ -> :ok
        end
      end)

      assert output =~ "not found" or output =~ "Error" or output =~ "exist"
    end

    test "supports --format json option" do
      output = capture_io(fn ->
        Mix.Tasks.Pristine.Validate.run(["--manifest", @valid_fixture, "--format", "json"])
      end)

      # Should be valid JSON
      assert {:ok, _} = Jason.decode(String.trim(output))
    end

    test "requires --manifest argument" do
      output = capture_io(fn ->
        try do
          Mix.Tasks.Pristine.Validate.run([])
        catch
          :exit, _ -> :ok
        end
      end)

      assert output =~ "manifest" or output =~ "required" or output =~ "Usage"
    end
  end
end
```

3. **Implement Mix Task**:

```elixir
# /home/home/p/g/n/pristine/lib/mix/tasks/pristine.validate.ex
defmodule Mix.Tasks.Pristine.Validate do
  @moduledoc """
  Validates a Pristine manifest file.

  ## Usage

      mix pristine.validate --manifest path/to/manifest.json [--format text|json]

  ## Options

    * `--manifest` - Path to the manifest file (required)
    * `--format` - Output format: "text" (default) or "json"

  ## Examples

      mix pristine.validate --manifest api_manifest.json
      mix pristine.validate --manifest api_manifest.json --format json

  """

  use Mix.Task

  @shortdoc "Validate a Pristine manifest file"

  @switches [
    manifest: :string,
    format: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: @switches)

    manifest_path = Keyword.get(opts, :manifest)
    format = Keyword.get(opts, :format, "text")

    cond do
      is_nil(manifest_path) ->
        output_error("Missing required --manifest argument", format)
        print_usage()
        exit({:shutdown, 1})

      not File.exists?(manifest_path) ->
        output_error("Manifest file not found: #{manifest_path}", format)
        exit({:shutdown, 1})

      true ->
        validate_manifest(manifest_path, format)
    end
  end

  defp validate_manifest(path, format) do
    case Pristine.Manifest.load_file(path) do
      {:ok, manifest} ->
        output_success(manifest, format)

      {:error, errors} when is_list(errors) ->
        output_errors(errors, format)
        exit({:shutdown, 1})

      {:error, error} ->
        output_errors([error], format)
        exit({:shutdown, 1})
    end
  end

  defp output_success(manifest, "json") do
    result = %{
      valid: true,
      name: manifest.name,
      version: manifest.version,
      endpoint_count: length(manifest.endpoints),
      type_count: map_size(manifest.types)
    }

    Mix.shell().info(Jason.encode!(result, pretty: true))
  end

  defp output_success(manifest, _text) do
    Mix.shell().info("""
    ✓ Manifest is valid

      Name: #{manifest.name}
      Version: #{manifest.version}
      Endpoints: #{length(manifest.endpoints)}
      Types: #{map_size(manifest.types)}
    """)
  end

  defp output_error(message, "json") do
    result = %{valid: false, errors: [%{message: message}]}
    Mix.shell().error(Jason.encode!(result, pretty: true))
  end

  defp output_error(message, _text) do
    Mix.shell().error("Error: #{message}")
  end

  defp output_errors(errors, "json") do
    formatted = Enum.map(errors, &format_error_json/1)
    result = %{valid: false, errors: formatted}
    Mix.shell().error(Jason.encode!(result, pretty: true))
  end

  defp output_errors(errors, _text) do
    Mix.shell().error("✗ Manifest validation failed:\n")

    Enum.each(errors, fn error ->
      Mix.shell().error("  • #{format_error_text(error)}")
    end)
  end

  defp format_error_json(%{message: msg, path: path}) do
    %{message: msg, path: Enum.join(path, ".")}
  end

  defp format_error_json(%{message: msg}) do
    %{message: msg}
  end

  defp format_error_json(error) when is_binary(error) do
    %{message: error}
  end

  defp format_error_json(error) do
    %{message: inspect(error)}
  end

  defp format_error_text(%{message: msg, path: path}) do
    "#{Enum.join(path, ".")}: #{msg}"
  end

  defp format_error_text(%{message: msg}) do
    msg
  end

  defp format_error_text(error) when is_binary(error) do
    error
  end

  defp format_error_text(error) do
    inspect(error)
  end

  defp print_usage do
    Mix.shell().info("""

    Usage: mix pristine.validate --manifest PATH [--format text|json]

    Options:
      --manifest  Path to the manifest file (required)
      --format    Output format: text (default) or json
    """)
  end
end
```

4. **Run Tests**:
```bash
cd /home/home/p/g/n/pristine && mix test test/mix/tasks/pristine.validate_test.exs
```

---

### Task 0.5: Idempotency Header Support

**Gap Addressed**: GAP-017

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex`
- `/home/home/p/g/n/pristine/lib/pristine/core/context.ex`
- `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex`

**Files to Create**:
- `/home/home/p/g/n/pristine/test/pristine/core/pipeline_idempotency_test.exs`

**TDD Steps**:

1. **Write Tests First**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/core/pipeline_idempotency_test.exs
defmodule Pristine.Core.PipelineIdempotencyTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.{Context, Pipeline, Request}
  alias Pristine.Manifest.Endpoint

  describe "idempotency header" do
    test "adds idempotency header when endpoint has idempotency: true" do
      endpoint = %Endpoint{
        id: :test,
        method: :post,
        path: "/test",
        idempotency: true
      }

      context = %Context{
        idempotency_header: "X-Idempotency-Key"
      }

      request = Pipeline.build_request(endpoint, %{}, "application/json", context, [])

      assert Map.has_key?(request.headers, "X-Idempotency-Key")
      # Should be a UUID
      assert String.length(request.headers["X-Idempotency-Key"]) == 36
    end

    test "uses custom idempotency key from opts" do
      endpoint = %Endpoint{
        id: :test,
        method: :post,
        path: "/test",
        idempotency: true
      }

      context = %Context{
        idempotency_header: "X-Idempotency-Key"
      }

      request = Pipeline.build_request(endpoint, %{}, "application/json", context,
        idempotency_key: "custom-key-123"
      )

      assert request.headers["X-Idempotency-Key"] == "custom-key-123"
    end

    test "does not add header when endpoint has idempotency: false" do
      endpoint = %Endpoint{
        id: :test,
        method: :post,
        path: "/test",
        idempotency: false
      }

      context = %Context{
        idempotency_header: "X-Idempotency-Key"
      }

      request = Pipeline.build_request(endpoint, %{}, "application/json", context, [])

      refute Map.has_key?(request.headers, "X-Idempotency-Key")
    end

    test "does not add header when idempotency is nil" do
      endpoint = %Endpoint{
        id: :test,
        method: :post,
        path: "/test",
        idempotency: nil
      }

      context = %Context{
        idempotency_header: "X-Idempotency-Key"
      }

      request = Pipeline.build_request(endpoint, %{}, "application/json", context, [])

      refute Map.has_key?(request.headers, "X-Idempotency-Key")
    end
  end
end
```

2. **Update Endpoint struct**:

Add to `/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex`:

```elixir
defstruct [
  # ... existing fields ...
  idempotency: false  # NEW: Enable idempotency header for this endpoint
]

@type t :: %__MODULE__{
  # ... existing types ...
  idempotency: boolean()
}
```

3. **Update Context struct**:

Add to `/home/home/p/g/n/pristine/lib/pristine/core/context.ex`:

```elixir
defstruct [
  # ... existing fields ...
  idempotency_header: "X-Idempotency-Key"  # NEW: Header name for idempotency
]

@type t :: %__MODULE__{
  # ... existing types ...
  idempotency_header: String.t()
}
```

4. **Update Pipeline**:

Add to `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex`:

```elixir
defp maybe_add_idempotency(headers, %{idempotency: true}, context, opts) do
  header_name = context.idempotency_header || "X-Idempotency-Key"
  key = Keyword.get(opts, :idempotency_key) || generate_idempotency_key()
  Map.put(headers, header_name, key)
end

defp maybe_add_idempotency(headers, _endpoint, _context, _opts) do
  headers
end

defp generate_idempotency_key do
  UUID.uuid4()
end
```

5. **Run Tests**:
```bash
cd /home/home/p/g/n/pristine && mix test test/pristine/core/pipeline_idempotency_test.exs
```

---

## Verification Checklist

After completing all tasks, verify:

```bash
# In Pristine
cd /home/home/p/g/n/pristine

# All tests pass
mix test

# No compilation warnings
mix compile --warnings-as-errors

# Credo passes
mix credo --strict

# Dialyzer passes
mix dialyzer

# In Sinter (if modified)
cd /home/home/p/g/n/sinter

mix test
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
```

---

## Expected Outcomes

After Stage 0 completion:

1. **Codegen produces documented functions** with @doc and @spec
2. **Sinter supports {:literal, value}** type with JSON Schema generation
3. **`mix pristine.validate`** works with text and JSON output
4. **Idempotency headers** are automatically added when configured
5. **Dialyzer and Credo** are configured and passing
6. **All tests pass** with no warnings or errors
