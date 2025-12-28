# CLI/Tools Architecture Audit: Tinker Python SDK vs Pristine

**Date:** 2025-12-28
**Scope:** CLI commands, documentation generation, testing infrastructure, and build/release tooling

---

## 1. Summary

The Tinker Python SDK includes a comprehensive CLI infrastructure built on Click with lazy loading for fast startup, a documentation generation system using pydoc-markdown, and standard Python build tooling (hatch/uv). Pristine currently has a single Mix task for code generation, leaving substantial gaps in developer tooling.

### Key Findings

| Capability | Tinker Python SDK | Pristine |
|------------|------------------|----------|
| CLI Framework | Click with LazyGroup | Mix tasks only |
| Commands | checkpoint, run, version | generate only |
| Doc Generation | pydoc-markdown with custom scripts | None |
| Build System | hatch/uv with PyPI publishing | Mix with Hex (incomplete) |
| Test Infrastructure | pytest with mocks, async support | Basic ExUnit |
| Type Checking | mypy + pyright (strict mode) | Dialyzer (not configured) |
| Linting | ruff (comprehensive rules) | None |

---

## 2. Detailed Analysis

### 2.1 Tinker CLI Architecture

**Source:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/`

The CLI is structured as a modular, lazy-loaded system:

```
cli/
  __main__.py      # Entry point with LazyGroup
  lazy_group.py    # Custom Click Group for lazy loading
  output.py        # OutputBase class for table/JSON rendering
  client.py        # SDK client creation and error handling
  context.py       # CLIContext dataclass for shared state
  exceptions.py    # TinkerCliError for graceful exits
  commands/
    checkpoint.py  # Checkpoint management (list, info, download, publish, delete)
    run.py         # Training run management (list, info)
    version.py     # Version display
```

#### Entry Point Configuration
**Source:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/pyproject.toml` (lines 42-43)

```toml
[project.scripts]
tinker = "tinker.cli.__main__:cli"
```

#### LazyGroup Pattern
**Source:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/lazy_group.py`

The LazyGroup class enables fast CLI startup (<50ms target) by deferring command imports:

```python
class LazyGroup(click.Group):
    def __init__(self, *args, lazy_subcommands=None, **kwargs):
        self.lazy_subcommands = lazy_subcommands or {}

    def get_command(self, ctx, cmd_name):
        if cmd_name in self.lazy_subcommands:
            import_path = self.lazy_subcommands[cmd_name]
            module_name, attr_name = import_path.rsplit(":", 1)
            mod = importlib.import_module(module_name)
            return getattr(mod, attr_name)
```

#### CLI Commands Summary

**Source:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/__main__.py` (lines 17-24)

```python
@click.group(
    cls=LazyGroup,
    lazy_subcommands={
        "checkpoint": "tinker.cli.commands.checkpoint:cli",
        "run": "tinker.cli.commands.run:cli",
        "version": "tinker.cli.commands.version:cli",
    },
)
```

| Command | Subcommands | Purpose |
|---------|-------------|---------|
| `tinker checkpoint` | list, info, download, publish, unpublish, delete | Checkpoint management |
| `tinker run` | list, info | Training run management |
| `tinker version` | (none) | Display version |

#### Output System
**Source:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/output.py`

Abstract base class for structured output supporting both table (rich) and JSON formats:

```python
class OutputBase(ABC):
    @abstractmethod
    def to_dict(self) -> Dict[str, Any]: pass

    @abstractmethod
    def get_table_columns(self) -> List[str]: pass

    @abstractmethod
    def get_table_rows(self) -> List[List[str]]: pass

    def print(self, format: str = "table") -> None:
        if format == "json":
            self._print_json()
        else:
            self._print_table()
```

#### Error Handling
**Source:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/client.py`

Centralized API error handling with user-friendly messages:

```python
@handle_api_errors
def wrapper(*args, **kwargs):
    try:
        return func(*args, **kwargs)
    except NotFoundError as e:
        raise TinkerCliError("Resource not found", details)
    except AuthenticationError as e:
        raise TinkerCliError("Authentication failed", details)
    # ... more error types
```

### 2.2 Documentation Generation

**Source:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/scripts/generate_docs.py`

Custom documentation generator that:
1. Parses Python modules using AST to extract `__all__` exports
2. Uses pydoc-markdown with custom configuration
3. Generates Nextra-compatible markdown
4. Creates `_meta.json` for navigation structure

```python
class DocumentationGenerator:
    def generate_all(self):
        self.generate_public_interfaces()  # ServiceClient, TrainingClient, etc.
        self.generate_all_types()          # All types reference
        self.generate_exceptions()         # Exception hierarchy
        self.generate_nextra_meta()        # Navigation metadata
```

**Configuration:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/pydoc-markdown.yml`

```yaml
processors:
  - type: filter
    documented_only: true
    exclude_private: true
    exclude_special: true
    skip_empty_modules: true

renderer:
  type: markdown
  classdef_code_block: true
  signature_code_block: true
```

**Generated Output:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/docs/api/`
- `serviceclient.md`
- `trainingclient.md`
- `samplingclient.md`
- `restclient.md`
- `apifuture.md`
- `types.md`
- `exceptions.md`
- `_meta.json`

### 2.3 Testing Infrastructure

**Source:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/pyproject.toml` (lines 112-120)

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--tb=short -n auto"
xfail_strict = true
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "session"
```

**Test Structure:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/tests/`
- `mock_api_server.py` - HTTP mock server
- `conftest.py` - Shared fixtures
- `test_client.py` - Client tests (83KB - comprehensive)
- `test_models.py` - Type/model tests (27KB)
- `test_streaming.py` - Streaming tests
- `test_response.py` - Response parsing tests
- And more...

### 2.4 Build and Release Tooling

**Build System:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/pyproject.toml`

```toml
[build-system]
requires = ["hatchling==1.26.3", "hatch-fancy-pypi-readme"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/tinker"]
```

**Publishing:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/scripts/publish-pypi`

```bash
#!/usr/bin/env bash
set -eux
rm -rf dist
mkdir -p dist
uv build
uv publish --token=$PYPI_TOKEN
```

**Type Checking:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/mypy.ini` and `/home/home/p/g/North-Shore-AI/tinkex/tinker/pyproject.toml`

Both mypy and pyright configured in strict mode:
```toml
[tool.pyright]
typeCheckingMode = "strict"
pythonVersion = "3.8"
reportImplicitOverride = true
```

**Linting:** `/home/home/p/g/North-Shore-AI/tinkex/tinker/.ruff.toml`

Comprehensive ruff configuration covering:
- isort for imports
- bugbear rules
- unused imports/arguments
- type checking imports

---

## 3. Pristine Equivalent: Current State

### 3.1 Mix Task for Code Generation

**Source:** `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.generate.ex`

Single Mix task for generating Elixir modules from manifests:

```elixir
defmodule Mix.Tasks.Pristine.Generate do
  use Mix.Task

  @shortdoc "Generate Pristine modules from a manifest"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [manifest: :string, output: :string, namespace: :string])

    with {:ok, manifest} <- Pristine.Manifest.load_file(manifest_path),
         {:ok, sources} <- Codegen.build_sources(manifest, ...) do
      Codegen.write_sources(sources)
    end
  end
end
```

**Usage:**
```bash
mix pristine.generate --manifest path/to/manifest.json --output lib/generated
```

### 3.2 Codegen Orchestration

**Source:** `/home/home/p/g/n/pristine/lib/pristine/codegen.ex`

```elixir
defmodule Pristine.Codegen do
  def build_sources(manifest_input, opts \\ []) do
    # Generate type modules
    type_sources = Enum.map(manifest.types, fn {name, defn} ->
      module_source = ElixirCodegen.render_type_module(...)
      {path, module_source}
    end)

    # Generate client module
    client_source = ElixirCodegen.render_client_module(...)

    {:ok, Map.put(type_sources, client_path, client_source)}
  end
end
```

### 3.3 Elixir Code Generator

**Source:** `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex`

Generates:
- Type modules with Sinter schema definitions
- Client module with endpoint functions
- Runtime execution wiring

---

## 4. Gap Analysis

### 4.1 CLI Tooling Gaps

| Feature | Tinker | Pristine | Gap Severity |
|---------|--------|----------|--------------|
| Interactive CLI | Click with rich output | None | **High** |
| Checkpoint/resource management | Full CRUD | None | Medium |
| Version command | Yes | None | Low |
| Output formats (JSON/table) | Both | N/A | Medium |
| Progress indicators | Yes | None | Low |
| Error handling framework | TinkerCliError | None | Medium |

### 4.2 Documentation Gaps

| Feature | Tinker | Pristine | Gap Severity |
|---------|--------|----------|--------------|
| API doc generation | pydoc-markdown | None | **High** |
| Type documentation | Auto-generated | None | **High** |
| Nextra/static site integration | Yes | None | Medium |
| Module analysis | AST parsing | None | Medium |

### 4.3 Testing Infrastructure Gaps

| Feature | Tinker | Pristine | Gap Severity |
|---------|--------|----------|--------------|
| Mock server | Yes | None | **High** |
| Shared fixtures | conftest.py | None | Medium |
| Async test support | pytest-asyncio | None | Medium |
| Parallel test execution | pytest-xdist | ExUnit async | Low |

### 4.4 Build/Quality Gaps

| Feature | Tinker | Pristine | Gap Severity |
|---------|--------|----------|--------------|
| Type checking | mypy + pyright strict | Dialyzer (not configured) | **High** |
| Linting | ruff (comprehensive) | None | Medium |
| Publishing script | Yes | None | Medium |

---

## 5. Recommended Changes

### 5.1 Additional Mix Tasks Needed

#### mix pristine.docs
Generate documentation from manifests:

```elixir
defmodule Mix.Tasks.Pristine.Docs do
  use Mix.Task

  @shortdoc "Generate API documentation from manifest"

  def run(args) do
    # Parse manifest
    # Generate:
    #   - ExDoc-compatible module docs
    #   - OpenAPI spec (see 5.3)
    #   - Type reference markdown
  end
end
```

#### mix pristine.validate
Validate manifests before code generation:

```elixir
defmodule Mix.Tasks.Pristine.Validate do
  use Mix.Task

  @shortdoc "Validate a Pristine manifest"

  def run(args) do
    # Load manifest
    # Run all validation rules
    # Report errors with line numbers
  end
end
```

#### mix pristine.diff
Show changes between generated code and current:

```elixir
defmodule Mix.Tasks.Pristine.Diff do
  use Mix.Task

  @shortdoc "Show pending codegen changes"

  def run(args) do
    # Build sources without writing
    # Compare against existing files
    # Display diff
  end
end
```

### 5.2 Documentation Generation from Manifests

Create `Pristine.Docs` module that:

1. **Extracts documentation from manifest types**
   - Field descriptions
   - Type constraints
   - Examples

2. **Generates ExDoc-compatible documentation**
   - Module-level @moduledoc
   - Function @doc annotations
   - Typespecs

3. **Produces static reference markdown**
   - Endpoint reference
   - Type catalog
   - Policy documentation

### 5.3 OpenAPI Spec Integration

Leverage Sinter's JSON Schema generation for OpenAPI:

**Source:** `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`

```elixir
defmodule Pristine.OpenAPI do
  @doc """
  Generate OpenAPI 3.1 spec from a Pristine manifest.
  """
  def generate(%Manifest{} = manifest, opts \\ []) do
    %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => manifest.name,
        "version" => manifest.version
      },
      "paths" => generate_paths(manifest.endpoints),
      "components" => %{
        "schemas" => generate_schemas(manifest.types)
      }
    }
  end

  defp generate_schemas(types) do
    Enum.map(types, fn {name, type_def} ->
      schema = Sinter.Schema.define(type_def.fields)
      {name, Sinter.JsonSchema.generate(schema)}
    end)
    |> Map.new()
  end
end
```

**Mix Task:**

```elixir
defmodule Mix.Tasks.Pristine.Openapi do
  use Mix.Task

  @shortdoc "Generate OpenAPI spec from manifest"

  def run(args) do
    # Load manifest
    # Generate OpenAPI spec
    # Write to openapi.json/yaml
  end
end
```

### 5.4 Testing Infrastructure

Create `Pristine.Test` module providing:

1. **Mock Server Builder**
   ```elixir
   defmodule Pristine.Test.MockServer do
     def build(manifest) do
       # Generate Plug router from manifest endpoints
       # Return module for use with Bypass
     end
   end
   ```

2. **Fixture Helpers**
   ```elixir
   defmodule Pristine.Test.Fixtures do
     def sample_manifest(overrides \\ [])
     def sample_context(overrides \\ [])
     def sample_payload(endpoint_id, overrides \\ [])
   end
   ```

3. **Assertion Helpers**
   ```elixir
   defmodule Pristine.Test.Assertions do
     def assert_valid_manifest(manifest)
     def assert_valid_response(response, manifest, endpoint_id)
   end
   ```

---

## 6. Concrete Next Steps (TDD Approach)

### Priority 1: Validation Mix Task (Week 1)

**Test First:**
```elixir
# test/mix/tasks/pristine.validate_test.exs

describe "run/1" do
  test "validates a correct manifest file" do
    assert capture_io(fn ->
      Mix.Tasks.Pristine.Validate.run(["--manifest", "test/fixtures/valid.json"])
    end) =~ "Manifest is valid"
  end

  test "reports errors for invalid manifest" do
    assert capture_io(fn ->
      Mix.Tasks.Pristine.Validate.run(["--manifest", "test/fixtures/invalid.json"])
    end) =~ "endpoints are required"
  end

  test "validates manifest from stdin with --stdin flag" do
    # ...
  end
end
```

**Implementation:**
1. Create `Mix.Tasks.Pristine.Validate`
2. Add rich error reporting with file/line context
3. Support `--format json` for CI integration

### Priority 2: OpenAPI Generation (Week 2)

**Test First:**
```elixir
# test/pristine/openapi_test.exs

describe "generate/2" do
  test "produces valid OpenAPI 3.1 spec" do
    manifest = sample_manifest()
    spec = Pristine.OpenAPI.generate(manifest)

    assert spec["openapi"] == "3.1.0"
    assert spec["info"]["title"] == manifest.name
    assert Map.has_key?(spec["paths"], "/sampling")
  end

  test "generates schemas for all types" do
    manifest = sample_manifest_with_types()
    spec = Pristine.OpenAPI.generate(manifest)

    assert Map.has_key?(spec["components"]["schemas"], "SampleRequest")
  end

  test "maps Sinter constraints to JSON Schema" do
    # Leverage Sinter.JsonSchema tests
  end
end
```

**Mix Task Test:**
```elixir
# test/mix/tasks/pristine.openapi_test.exs

describe "run/1" do
  test "generates openapi.json from manifest" do
    Mix.Tasks.Pristine.Openapi.run([
      "--manifest", "test/fixtures/sample.json",
      "--output", tmp_path
    ])

    assert File.exists?(Path.join(tmp_path, "openapi.json"))
  end

  test "supports yaml output format" do
    # ...
  end
end
```

### Priority 3: Test Fixtures Module (Week 2-3)

**Test First:**
```elixir
# test/pristine/test/fixtures_test.exs

describe "sample_manifest/1" do
  test "returns valid manifest" do
    manifest = Fixtures.sample_manifest()
    assert {:ok, _} = Pristine.Manifest.load(manifest)
  end

  test "allows overriding name" do
    manifest = Fixtures.sample_manifest(name: "custom")
    assert manifest.name == "custom"
  end
end
```

### Priority 4: Documentation Generation (Week 3-4)

**Test First:**
```elixir
# test/mix/tasks/pristine.docs_test.exs

describe "run/1" do
  test "generates type documentation" do
    Mix.Tasks.Pristine.Docs.run([
      "--manifest", fixture_path,
      "--output", tmp_path
    ])

    docs_content = File.read!(Path.join(tmp_path, "types.md"))
    assert docs_content =~ "## SampleRequest"
    assert docs_content =~ "prompt: string (required)"
  end
end
```

### Priority 5: Dialyzer/Credo Configuration (Week 4)

**Add to mix.exs:**
```elixir
defp deps do
  [
    # ... existing deps ...
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
  ]
end
```

**Create .credo.exs:**
```elixir
%{
  configs: [
    %{
      name: "default",
      checks: %{
        enabled: [
          {Credo.Check.Consistency.TabsOrSpaces, []},
          {Credo.Check.Design.AliasUsage, []},
          {Credo.Check.Readability.ModuleDoc, []},
          # ... comprehensive rules
        ]
      }
    }
  ]
}
```

---

## 7. Architecture Decision: Manifest-Driven vs External Tooling

### Should Be Manifest-Driven (Internal to Pristine)

1. **Code Generation** - Already implemented
2. **Validation** - Manifest schema is self-describing
3. **OpenAPI Generation** - Direct translation from manifest
4. **Type Documentation** - Extracted from type definitions
5. **Mock Server Generation** - Derived from endpoints

### Should Be External Tooling (Mix Tasks/Plugins)

1. **CLI for Resource Management** - Application-specific (like Tinker's checkpoint/run commands)
2. **Publishing/Release** - Standard Hex tooling
3. **Linting** - Credo (language-level)
4. **Type Checking** - Dialyzer (language-level)

### Hybrid Approach

1. **Documentation Generation**
   - Manifest-driven: Extract docs from manifest
   - External: ExDoc integration for final rendering

2. **Testing Infrastructure**
   - Manifest-driven: Generate mock responses from types
   - External: Bypass/Mox for actual HTTP mocking

---

## 8. File References

### Tinker Python SDK
- CLI entry: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/__main__.py`
- LazyGroup: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/lazy_group.py`
- Output base: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/output.py`
- Client utilities: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/client.py`
- Checkpoint commands: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/commands/checkpoint.py`
- Run commands: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/commands/run.py`
- Doc generation: `/home/home/p/g/North-Shore-AI/tinkex/tinker/scripts/generate_docs.py`
- Build config: `/home/home/p/g/North-Shore-AI/tinkex/tinker/pyproject.toml`
- Type checking: `/home/home/p/g/North-Shore-AI/tinkex/tinker/mypy.ini`
- Linting: `/home/home/p/g/North-Shore-AI/tinkex/tinker/.ruff.toml`

### Pristine Elixir
- Generate task: `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.generate.ex`
- Codegen: `/home/home/p/g/n/pristine/lib/pristine/codegen.ex`
- Elixir codegen: `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex`
- Manifest: `/home/home/p/g/n/pristine/lib/pristine/manifest.ex`
- Main module: `/home/home/p/g/n/pristine/lib/pristine.ex`
- Mix config: `/home/home/p/g/n/pristine/mix.exs`

### Sinter (for JSON Schema)
- JSON Schema generation: `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`

### Tinkex Elixir
- Mix config: `/home/home/p/g/North-Shore-AI/tinkex/mix.exs`
