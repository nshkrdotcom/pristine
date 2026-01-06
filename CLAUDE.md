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
