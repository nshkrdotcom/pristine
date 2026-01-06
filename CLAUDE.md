# Pristine

Manifest-driven, hexagonal SDK generator for Elixir. Separates domain logic from infrastructure via ports and adapters.

## Project Structure

```
lib/pristine/
├── core/           # Domain logic (pipeline, request, response, context)
├── ports/          # Interface contracts (transport, serializer, retry, etc.)
├── adapters/       # Implementations (finch, json, foundation, etc.)
├── codegen/        # Code generation pipeline
├── streaming/      # SSE support
├── manifest/       # Manifest loading and validation
examples/
├── tinkex/         # Tinkex SDK port (in progress)
docs/
├── 20250105/       # Current sprint documentation
```

## Dependencies (Local)

- `foundation` - Retry, backoff, circuit breaker, rate limiting
- `sinter` - Schema validation, JSON Schema generation
- `multipart_ex` - Multipart/form-data encoding
- `telemetry_reporter` - Telemetry batching and transport

## Commands

```bash
# Run tests
mix test

# Run specific test file
mix test test/path/to/test.exs

# Type checking
mix dialyzer

# Linting
mix credo --strict

# Format
mix format

# All checks
mix test && mix dialyzer && mix credo --strict
```

## Testing Standards (Supertester)

**ALL tests in this project MUST use [supertester](../supertester) for proper test isolation.** There are ZERO exceptions. Test ordering issues and flaky tests are unacceptable.

### Mandatory Requirements

1. **Use `Supertester.ExUnitFoundation`** with `isolation: :full_isolation` in all test modules
2. **Zero `Process.sleep`** - Use `cast_and_sync/2`, `wait_for_*` helpers instead
3. **Use `setup_isolated_genserver/3`** and `setup_isolated_supervisor/3` for all OTP processes
4. **All tests MUST run with `async: true`** - No sequential tests due to isolation issues
5. **Automatic cleanup** - Let supertester handle all resource cleanup

### Test Module Template

```elixir
defmodule MyApp.MyTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions

  test "example with isolated GenServer" do
    {:ok, server} = setup_isolated_genserver(MyServer)
    :ok = cast_and_sync(server, :some_message)
    assert_genserver_state(server, fn state -> state.count == 1 end)
  end
end
```

### Forbidden Patterns

- ❌ `Process.sleep/1` in tests
- ❌ `async: false` due to test isolation issues
- ❌ Manual GenServer/Supervisor start without supertester
- ❌ Tests that depend on execution order
- ❌ Global state or named processes without isolation

### Running Tests

```bash
# All tests must pass with any seed
mix test --seed 0
mix test --seed 12345
mix test  # random seed
```

## Tinkex Port Workflow

The `examples/tinkex` directory contains an ongoing port of `~/p/g/North-Shore-AI/tinkex`.

### Iterative Development Process

1. **Gap Analysis** - Compare source tinkex with port, identify missing functionality
2. **Documentation** - Update gap analysis docs and checklist
3. **TDD/RGR** - Test-driven development with Red-Green-Refactor cycle

### Running the Port Prompt

```bash
# Start iterative development session
cat docs/20250105/TINKEX_PORT_PROMPT.md
```

The prompt is designed for repeated execution - each agent picks up where the previous left off.

## Key Files

- `docs/20250105/TINKEX_PORT_PROMPT.md` - Main iterative development prompt
- `docs/20250105/GAP_ANALYSIS.md` - Current gap analysis (auto-maintained)
- `docs/20250105/CHECKLIST.md` - Implementation checklist (auto-maintained)
- `examples/tinkex/` - The ported tinkex implementation

## Architecture Notes

- **Hexagonal**: Ports define contracts, adapters implement them
- **Manifest-driven**: API definitions in JSON/YAML drive code generation
- **Type-safe**: Sinter schemas validate requests/responses
- **Observable**: Telemetry throughout the pipeline

## Implementation Status

**Current Phase**: Phase 0 - Project Setup (Test Fixes)
**Last Updated**: 2026-01-06

### Completed
- [x] Architecture documentation (docs/20260106/)
- [x] ARCHITECTURE.md - Overall design
- [x] DELINEATION.md - What goes where (Pristine vs Tinkex)
- [x] PRISTINE_EXTENSIONS.md - Required Pristine additions
- [x] TINKEX_MINIMAL.md - Thin tinkex specification
- [x] MIGRATION_PLAN.md - Implementation phases with TDD
- [x] Existing lib/tinkex files ported
- [x] Existing test files created
- [x] Phase 0 setup files:
  - [x] Create mix.exs with pristine path dep
  - [x] Create .gitignore
  - [x] Create .formatter.exs
  - [x] Add supertester as test dependency
  - [x] Update test/test_helper.exs

### In Progress
- [ ] Phase 0: Fix test suite with supertester isolation
  - [ ] Fix SamplingClientObservabilityTest (8 failures - log capture)
  - [ ] Fix TrainingClient encode test (1 failure - tokenizer)
  - [ ] Verify: `mix test --seed 0` and `mix test --seed 12345` both pass

### Next Up
- [ ] Phase 1: Pristine Extensions (compression, bytes semaphore, session mgmt, env utils)
- [ ] Phase 2: Tinkex Manifest (define all API endpoints)
- [ ] Phase 3: Tinkex Types with Sinter validation
- [ ] Phase 4: Core Clients (ServiceClient, TrainingClient, SamplingClient, RestClient)
- [ ] Phase 5: Domain Features (Regularizers, Recovery, Streaming)
- [ ] Phase 6: CLI (Optional)
- [ ] Phase 7: Integration Testing

### Blockers/Decisions
- Test failures must be fixed with proper supertester isolation before proceeding
