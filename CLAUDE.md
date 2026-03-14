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

## Architecture Notes

- **Hexagonal**: Ports define contracts, adapters implement them
- **Manifest-driven**: API definitions in JSON/YAML drive code generation
- **Type-safe**: Sinter schemas validate requests/responses
- **Observable**: Telemetry throughout the pipeline

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
