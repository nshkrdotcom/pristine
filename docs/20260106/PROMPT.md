# Pristine + Tinkex Implementation Prompt

This prompt is designed to run **iteratively**. Each execution picks up where the previous left off.

---

## Initial Actions (Every Run)

### 1. Read and Assess Status

**FIRST**, read the following files to understand current state:

```
REQUIRED READING (in order):
1. /home/home/p/g/n/pristine/CLAUDE.md          - Project instructions and current status
2. /home/home/p/g/n/pristine/docs/20260106/ARCHITECTURE.md
3. /home/home/p/g/n/pristine/docs/20260106/DELINEATION.md
4. /home/home/p/g/n/pristine/docs/20260106/PRISTINE_EXTENSIONS.md
5. /home/home/p/g/n/pristine/docs/20260106/TINKEX_MINIMAL.md
6. /home/home/p/g/n/pristine/docs/20260106/MIGRATION_PLAN.md
```

### 2. Update CLAUDE.md with Current Status

After reading, **update CLAUDE.md** with:
- Current phase of implementation
- What's completed
- What's in progress
- What's next
- Any blockers or decisions needed

Use this format in CLAUDE.md under a `## Implementation Status` section:

```markdown
## Implementation Status

**Current Phase**: [Phase X: Name]
**Last Updated**: [Date]

### Completed
- [ ] Item 1
- [ ] Item 2

### In Progress
- [ ] Current task

### Next Up
- [ ] Next task

### Blockers/Decisions
- None / List any
```

---

## Reference Material

### Original Tinkex (Source of Truth)

```
~/p/g/North-Shore-AI/tinkex/
├── lib/tinkex/           # ALL functionality to port
├── test/                 # Reference tests
└── mix.exs               # Dependencies reference
```

**Every feature in original tinkex MUST be implemented.**

### Local Dependencies (Used by Pristine)

| Dep | Path | Purpose |
|-----|------|---------|
| foundation | ~/p/g/n/foundation | Retry, backoff, circuit breaker, rate limiting |
| sinter | ~/p/g/n/sinter | Schema validation (ALL type validation) |
| multipart_ex | ~/p/g/n/multipart_ex | Multipart/form-data encoding |
| telemetry_reporter | ~/p/g/n/telemetry_reporter | Telemetry batching and transport |
| supertester | ~/p/g/n/supertester | Test isolation, OTP testing, chaos engineering |

**Read these when implementing related functionality.**

---

## Architecture Rules

### Rule 1: Pristine Gets Infrastructure

**ALL** generalizable SDK infrastructure goes into `lib/pristine/`:

- HTTP transport (Finch adapter)
- Retry logic (via foundation)
- Circuit breaker (via foundation)
- Rate limiting (via foundation)
- Telemetry (via telemetry_reporter)
- Schema validation (via sinter)
- Multipart encoding (via multipart_ex)
- SSE streaming
- Future/polling
- Session management
- Error handling
- File utilities
- Environment config

### Rule 2: Tinkex Gets Domain Logic Only

`examples/tinkex/` contains ONLY:

- ML types (ModelInput, TensorData, Datum, etc.)
- Training loop logic (TrainingClient)
- Sampling logic (SamplingClient)
- Regularizers
- Recovery (training-specific parts)
- HuggingFace integration
- API manifest definition

**Tinkex must NOT duplicate ANY Pristine functionality.**

### Rule 3: Standalone Mix App

`examples/tinkex/` is a **standalone Mix application**:

```elixir
# examples/tinkex/mix.exs
defp deps do
  [
    {:pristine, path: "../../"},  # ONLY runtime dep
    {:mox, "~> 1.0", only: :test}
  ]
end
```

Must have:
- Own `mix.exs`
- Own `.gitignore`
- Own `.formatter.exs`
- Own test suite
- Can compile/test independently: `cd examples/tinkex && mix test`

### Rule 4: Sinter for ALL Schemas

Use `sinter` for ALL type validation. No manual schema code:

```elixir
# WRONG - manual validation
def validate(%MyType{} = t) do
  cond do
    is_nil(t.field) -> {:error, "field required"}
    ...
  end
end

# RIGHT - sinter schema
defmodule MyType do
  use Sinter.Schema

  schema do
    field :name, :string, required: true
    field :count, :integer, default: 0
  end
end
```

### Rule 5: Foundation for Resilience

Use `foundation` for ALL resilience patterns:

```elixir
# Retry via Foundation
Foundation.Retry.with_retry(fn -> do_request() end, max_attempts: 3)

# Circuit breaker via Foundation
Foundation.CircuitBreaker.call(:my_breaker, fn -> do_request() end)

# Rate limiting via Foundation
Foundation.RateLimit.within_limit(fn -> do_request() end, key: :api)
```

### Rule 6: Supertester for ALL Tests

**ALL tests MUST use supertester.** Zero exceptions. Test isolation issues are bugs.

```elixir
# WRONG - basic ExUnit without isolation
defmodule MyTest do
  use ExUnit.Case, async: false  # ❌ No isolation

  test "bad test" do
    {:ok, pid} = MyServer.start_link(name: MyServer)  # ❌ Named process
    Process.sleep(100)  # ❌ Sleep
    # ...
  end
end

# RIGHT - supertester with full isolation
defmodule MyTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions

  test "good test" do
    {:ok, pid} = setup_isolated_genserver(MyServer)  # ✅ Isolated
    :ok = cast_and_sync(pid, :work)  # ✅ No sleep
    assert_genserver_state(pid, &match?(%{ready: true}, &1))  # ✅ OTP assertion
  end
end
```

---

## TDD/RGR Methodology

**EVERY** implementation follows Red-Green-Refactor:

### Red Phase
1. Write failing test first
2. Test should describe expected behavior
3. Run test, confirm it fails

### Green Phase
1. Write minimal code to pass test
2. No extra features
3. Run test, confirm it passes

### Refactor Phase
1. Clean up code
2. Remove duplication
3. Improve naming
4. Run tests, confirm still passing

### Test Organization

```
# Pristine tests
test/pristine/
├── core/
│   └── pipeline_test.exs
├── ports/
│   └── *_test.exs
└── adapters/
    └── *_test.exs

# Tinkex tests (standalone)
examples/tinkex/test/
├── test_helper.exs
└── tinkex/
    ├── training_client_test.exs
    ├── sampling_client_test.exs
    └── types/
        └── *_test.exs
```

### Test Requirements (Supertester)

Every test file MUST:

1. Use `Supertester.ExUnitFoundation` with `isolation: :full_isolation`
2. Import `Supertester.OTPHelpers`, `GenServerHelpers`, `Assertions` as needed
3. Use `setup_isolated_genserver/3` for GenServer tests
4. Use `cast_and_sync/2` instead of `Process.sleep/1`
5. Pass with any random seed (`mix test --seed 0`, `mix test --seed 12345`)

---

## Implementation Phases

### Phase 0: Setup (if not done)

- [ ] Delete current `examples/tinkex/` (it's duplicated slop)
- [ ] Create fresh `examples/tinkex/` structure
- [ ] Create `examples/tinkex/mix.exs` with pristine path dep
- [ ] Create `examples/tinkex/.gitignore`
- [ ] Create `examples/tinkex/.formatter.exs`
- [ ] Create `examples/tinkex/test/test_helper.exs`
- [ ] Verify: `cd examples/tinkex && mix deps.get && mix compile`

### Phase 1: Pristine Extensions

Extend Pristine to support all tinkex needs:

- [ ] Enhanced error types (category, retry hints)
- [ ] Compression support (gzip)
- [ ] Bytes semaphore adapter
- [ ] Session management
- [ ] Environment utilities
- [ ] Telemetry capture macro
- [ ] File utilities

**TDD**: Write tests in `test/pristine/` first.

### Phase 2: Tinkex Manifest

- [ ] Create `examples/tinkex/priv/manifest.exs`
- [ ] Define ALL endpoints from original tinkex API modules
- [ ] Test manifest loading

### Phase 3: Tinkex Types

Port ALL types from `~/p/g/North-Shore-AI/tinkex/lib/tinkex/types/`:

- [ ] Use Sinter schemas for validation
- [ ] Keep ML-specific logic
- [ ] Remove infrastructure dependencies

**TDD**: Write type tests first.

### Phase 4: Core Clients

- [ ] ServiceClient (session management, client factory)
- [ ] TrainingClient (forward/backward/optim loop)
- [ ] SamplingClient (text generation, streaming)
- [ ] RestClient (checkpoint/session facade)

**TDD**: Write client tests with mocked Pristine pipeline.

### Phase 5: Domain Features

- [ ] Regularizers (behaviour + 8 implementations)
- [ ] Recovery (policy, monitor, behaviours)
- [ ] Streaming (SampleStream decoder)
- [ ] HuggingFace integration
- [ ] Checkpoint download

**TDD**: Write feature tests first.

### Phase 6: CLI (Optional)

If CLI is needed:
- [ ] Port CLI from original tinkex
- [ ] Could be separate app or in tinkex

### Phase 7: Integration Testing

- [ ] End-to-end tests against mock server
- [ ] Compatibility tests with original tinkex API
- [ ] Performance benchmarks

---

## Workflow Per Session

1. **Read CLAUDE.md** - Understand current status
2. **Update CLAUDE.md** - Mark what you're working on
3. **Pick next task** - From current phase
4. **TDD cycle**:
   - Write failing test
   - Implement to pass
   - Refactor
5. **Run all tests** - Ensure nothing broke
6. **Update CLAUDE.md** - Mark completed, note next steps

---

## Quality Gates

Before moving to next phase:

```bash
# In pristine root
mix test
mix dialyzer
mix credo --strict
mix format --check-formatted

# In examples/tinkex
cd examples/tinkex
mix test
mix format --check-formatted
```

---

## Final Actions (Every Run)

### Update CLAUDE.md

At the END of each session, update CLAUDE.md with:

1. What was completed this session
2. Current phase status
3. Next steps for following session
4. Any blockers or decisions needed

### Commit Checkpoint (if requested)

If user requests commit:
```bash
git add -A
git commit -m "feat(pristine/tinkex): [description]

- What was done
- Current status

🤖 Generated with Claude Code"
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project instructions, STATUS TRACKING |
| `docs/20260106/ARCHITECTURE.md` | Overall design |
| `docs/20260106/DELINEATION.md` | What goes where |
| `docs/20260106/PRISTINE_EXTENSIONS.md` | Pristine additions needed |
| `docs/20260106/TINKEX_MINIMAL.md` | Thin tinkex spec |
| `docs/20260106/MIGRATION_PLAN.md` | Implementation phases |
| `~/p/g/North-Shore-AI/tinkex/` | Original source (ALL features) |
| `~/p/g/n/foundation/` | Resilience dep |
| `~/p/g/n/sinter/` | Schema validation dep |
| `~/p/g/n/multipart_ex/` | Multipart dep |
| `~/p/g/n/telemetry_reporter/` | Telemetry dep |

---

## Remember

1. **Read CLAUDE.md first** - Always start by assessing status
2. **Update CLAUDE.md last** - Always end by recording progress
3. **TDD everything** - Tests before implementation
4. **Infrastructure → Pristine** - Never duplicate in tinkex
5. **Domain → Tinkex** - Keep ML logic in tinkex
6. **Use the deps** - foundation, sinter, multipart_ex, telemetry_reporter
7. **Standalone tinkex** - Must work as independent mix app
8. **ALL original features** - Nothing from original tinkex gets dropped
9. **Supertester mandatory** - ALL tests use supertester for isolation
