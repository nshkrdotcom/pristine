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

**Current Phase**: Phase 2 - Infrastructure Replacement (In Progress)
**Last Updated**: 2026-01-06
**Goal**: Downsize examples/tinkex from 22,357 lines to ~5,000 lines

### Completed
- [x] Architecture documentation (docs/20260106/)
- [x] Phase 0: Test Fixes
  - [x] Fixed Logger level pollution in LoggingTest (was setting global to :error)
  - [x] All 1702 tests pass with seed 0, 12345, and random
- [x] Analysis and Planning (docs/20260106/salvage-assessment/, tdd-downsize-plan/)
  - [x] Feature inventory: 173 files, 67 types, 5 clients, 8 regularizers
  - [x] Module mapping: 4 direct replacements, 5 need extensions, 80+ domain-specific
  - [x] TDD execution plan created
- [x] Phase 1: Pristine Extensions
  - [x] BytesSemaphore port + adapter (lib/pristine/ports/bytes_semaphore.ex)
  - [x] Compression port + adapter (lib/pristine/adapters/compression/gzip.ex)
  - [x] 33 new tests added to Pristine (387 total tests, all pass)
- [x] Phase 2 (partial): Infrastructure Replacement
  - [x] Tinkex.BytesSemaphore → thin wrapper (170 → 49 lines)
  - [x] Tinkex.API.Compression → delegates to Pristine.Adapters.Compression.Gzip

### In Progress
- [ ] Phase 2 (continued): More infrastructure replacements
  - [ ] Tinkex.Semaphore → Pristine.Adapters.Semaphore.Counting
  - [ ] API layer → Pristine.Core.Pipeline integration

### Next Up
- [ ] Phase 3: Create tinkex manifest (JSON/YAML API definition)
- [ ] Phase 4: Generate types from manifest (4,201 lines → generated)
- [ ] Phase 5: Wire HTTP to Pristine pipeline (2,641 lines API layer)
- [ ] Phase 6: Final cleanup

### Current Status
- **Tests**: 1702 passing (all seeds: 0, 12345, random)
- **Line Count**: 22,237 (reduced from 22,357)
- **Compilation**: Clean (no warnings)
- **Dialyzer**: Clean (no errors) for Pristine core
- **Credo**: Clean (no issues) for Pristine core

### Line Count Breakdown (Potential Savings)
| Component | Lines | Can Replace? | Potential |
|-----------|-------|--------------|-----------|
| Types (67 modules) | 4,201 | Generate from manifest | ~4,000 |
| API layer | 2,641 | Pristine pipeline | ~2,000 |
| Infrastructure | ~2,500 | Pristine ports | ~1,500 |
| Domain logic | ~13,000 | Keep (core SDK) | 0 |
| **Total potential** | - | - | **~7,500** |

### Key Documentation
- `docs/20260106/salvage-assessment/` - What to keep vs discard
- `docs/20260106/tdd-downsize-plan/EXECUTION_PLAN.md` - Detailed TDD phases
