---
active: true
iteration: 13
max_iterations: 50
completion_promise: null
started_at: "2026-01-06T08:54:28Z"
---

# Tinkex Port - Iterative Development Prompt

> **Purpose**: Self-sufficient prompt for iterative, multiagent-driven porting of  to 
>
> **Execution**: Run this prompt repeatedly. Each agent picks up from the previous agent's work.
>
> **Philosophy**: Assess → Analyze → Document → Implement (TDD/RGR)

---

## REQUIRED READING (Execute First)

Before any work, spawn parallel agents to read these critical files:


PARALLEL AGENT BATCH 1 - Project Context:
├── Agent 1: Read ./CLAUDE.md, ./mix.exs, ./README.md
├── Agent 2: Read ./examples/tinkex/ (all files if exists)
├── Agent 3: Read ~/p/g/North-Shore-AI/tinkex/mix.exs, ~/p/g/North-Shore-AI/tinkex/lib/tinkex.ex
└── Agent 4: Read ./docs/20250105/GAP_ANALYSIS.md, ./docs/20250105/CHECKLIST.md (if exist)

PARALLEL AGENT BATCH 2 - Source Understanding:
├── Agent 5: Explore ~/p/g/North-Shore-AI/tinkex/lib/ structure and module list
├── Agent 6: Explore ~/p/g/North-Shore-AI/tinkex/test/ structure
├── Agent 7: Read ~/p/g/North-Shore-AI/tinkex/lib/tinkex/types/ (first 5 type modules)
└── Agent 8: Read ./lib/pristine/ports/ and ./lib/pristine/adapters/ for integration points


---

## PHASE 1: STATE ASSESSMENT

### 1.1 Spawn Assessment Agents (Parallel)

Launch 4 parallel agents to assess current state:

**Agent A - Source Inventory**:

Explore ~/p/g/North-Shore-AI/tinkex comprehensively:
- Count all modules in lib/
- List all public functions per module
- Identify all type definitions (Tinkex.Types.*)
- List all examples in examples/
- Return structured inventory as markdown table


**Agent B - Port Inventory**:

Explore ./examples/tinkex (if exists):
- List all implemented modules
- List all test files
- Check for any compile errors (mix compile --warnings-as-errors)
- Run mix test if tests exist, capture results
- Return current implementation status


**Agent C - Dependency Check**:

Verify local dependencies are available and compatible:
- Check ~/p/g/n/foundation exists and compiles
- Check ~/p/g/n/sinter exists and compiles
- Check ~/p/g/n/multipart_ex exists and compiles
- Check ~/p/g/n/telemetry_reporter exists and compiles
- Return dependency health report


**Agent D - Documentation State**:

Read existing documentation:
- ./docs/20250105/GAP_ANALYSIS.md (if exists)
- ./docs/20250105/CHECKLIST.md (if exists)
- ./docs/20250105/*.md (any other docs)
- Return summary of documented progress


### 1.2 Synthesize Assessment

After all agents complete, synthesize findings into a **State Summary**:
- Total modules in source: N
- Total modules ported: M
- Completion percentage: M/N
- Failing tests: X
- Dialyzer errors: Y
- Credo issues: Z
- Next priority area: [identified from gaps]

---

## PHASE 2: GAP ANALYSIS

### 2.1 Spawn Gap Analysis Agents (Parallel)

Launch 6 parallel agents for deep gap analysis:

**Agent GA-1 - Core Client Gap**:

Compare source and port for core client modules:
SOURCE: ~/p/g/North-Shore-AI/tinkex/lib/tinkex/
- service_client.ex
- training_client.ex
- sampling_client.ex
- rest_client.ex

PORT: ./examples/tinkex/lib/tinkex/

For each module:
1. List all public functions in source
2. Check if function exists in port
3. Compare function signatures
4. Note any missing functionality

Output: Markdown table with columns [Module, Function, Source Arity, Port Status, Notes]


**Agent GA-2 - API Layer Gap**:

Compare API modules:
SOURCE: ~/p/g/North-Shore-AI/tinkex/lib/tinkex/api/
- All .ex files in api/ directory

PORT: ./examples/tinkex/lib/tinkex/api/ OR pristine adapters

For each API module, identify:
1. HTTP endpoints covered
2. Request/response types used
3. Missing endpoints in port

Output: Structured gap list


**Agent GA-3 - Types Gap**:

Compare type definitions:
SOURCE: ~/p/g/North-Shore-AI/tinkex/lib/tinkex/types/
- All type modules (67+ expected)

PORT: ./examples/tinkex/lib/tinkex/types/ OR sinter schemas

Identify:
1. Missing type modules
2. Missing fields in existing types
3. Type validation differences

Output: List of missing/incomplete types


**Agent GA-4 - Test Coverage Gap**:

Compare test coverage:
SOURCE: ~/p/g/North-Shore-AI/tinkex/test/
- List all test files
- Count test cases per file

PORT: ./examples/tinkex/test/

Identify:
1. Missing test files
2. Test files with fewer cases than source
3. Integration tests status

Output: Test gap analysis


**Agent GA-5 - Telemetry/Observability Gap**:

Compare observability features:
SOURCE: ~/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry/
- telemetry.ex
- reporter.ex
- metrics.ex
- otel.ex

Check pristine/foundation/telemetry_reporter integration points.

Output: Observability feature comparison


**Agent GA-6 - Resilience Gap**:

Compare resilience features:
SOURCE: ~/p/g/North-Shore-AI/tinkex/lib/tinkex/
- retry.ex, retry_handler.ex, retry_config.ex
- circuit_breaker.ex, circuit_breaker/
- rate_limiter.ex
- recovery/

Check pristine/foundation integration for these features.

Output: Resilience feature comparison


### 2.2 Update Gap Analysis Document

After all gap agents complete, update :

markdown
# Gap Analysis - [Date]

## Summary
- Source modules: X
- Ported modules: Y
- Gap: Z modules

## Module Status

### Core Clients
| Module | Status | Missing Functions | Priority |
|--------|--------|-------------------|----------|
| ServiceClient | Partial | create_*_async | High |
| ... | ... | ... | ... |

### API Layer
[Table of API gaps]

### Types
[List of missing types]

### Tests
[Test coverage gaps]

### Observability
[Feature gaps]

### Resilience
[Feature gaps]

## Priority Queue
1. [Highest priority item]
2. [Next priority]
3. ...


---

## PHASE 3: CHECKLIST MAINTENANCE

### 3.1 Update Implementation Checklist

Update  based on gap analysis:

markdown
# Implementation Checklist - [Date]

## Legend
- [ ] Not started
- [~] In progress
- [x] Complete
- [\!] Blocked

## Core Infrastructure
- [x] Project structure (examples/tinkex/)
- [x] mix.exs with dependencies
- [ ] Application supervisor
- [ ] Config module

## Core Clients
- [ ] Tinkex.ServiceClient
  - [ ] start_link/1
  - [ ] create_lora_training_client/3
  - [ ] create_sampling_client/2
  - [ ] ...
- [ ] Tinkex.TrainingClient
  - [ ] forward_backward/4
  - [ ] optim_step/2
  - [ ] ...

## Types (67 total)
- [ ] Tinkex.Types.Datum
- [ ] Tinkex.Types.ModelInput
- [ ] ...

## Tests
- [ ] Unit tests for core clients
- [ ] Integration tests
- [ ] Property-based tests

## Quality Gates
- [ ] mix compile --warnings-as-errors
- [ ] mix test (all passing)
- [ ] mix dialyzer (no errors)
- [ ] mix credo --strict (no issues)


---

## PHASE 4: IMPLEMENTATION (TDD/RGR)

### 4.1 Select Next Work Item

From the checklist, select the highest priority uncompleted item that:
1. Has all dependencies satisfied
2. Is not blocked
3. Maximizes value (core functionality first)

### 4.2 TDD Red Phase - Spawn Test Writer Agents (Parallel)

For the selected work item, launch parallel agents to write tests:

**Agent TDD-1 - Unit Test Writer**:

Write unit tests for [MODULE/FUNCTION]:

1. Read source implementation: ~/p/g/North-Shore-AI/tinkex/lib/[path]
2. Read source tests: ~/p/g/North-Shore-AI/tinkex/test/[path]
3. Write equivalent tests in ./examples/tinkex/test/[path]

Tests must:
- Cover all public functions
- Include edge cases
- Use Mox for external dependencies
- Follow source test patterns

Output: Test file content


**Agent TDD-2 - Integration Test Writer**:

Write integration tests for [MODULE]:

1. Identify integration points with other modules
2. Write tests that verify module interactions
3. Use Bypass for HTTP mocking if needed

Output: Integration test content


**Agent TDD-3 - Type Spec Writer**:

Write type specifications:

1. Read source @spec and @type definitions
2. Ensure all public functions have specs
3. Create type modules if needed (using Sinter schemas)

Output: Type specifications


### 4.3 Verify Red (Tests Fail)

Run tests to confirm they fail (red phase):

bash
mix test test/path/to/new_test.exs
# Should fail - implementation doesn't exist yet


### 4.4 TDD Green Phase - Spawn Implementation Agents (Parallel)

**Agent IMPL-1 - Core Implementation**:

Implement [MODULE/FUNCTION]:

1. Read source: ~/p/g/North-Shore-AI/tinkex/lib/[path]
2. Read failing tests: ./examples/tinkex/test/[path]
3. Implement minimal code to pass tests

Use pristine infrastructure where appropriate:
- Pristine.Core.Pipeline for request execution
- Pristine.Ports.* for interface contracts
- Foundation.* for resilience
- Sinter.* for validation

Output: Implementation code


**Agent IMPL-2 - Adapter Implementation**:

If module needs pristine adapters:

1. Check if adapter exists in ./lib/pristine/adapters/
2. If not, create adapter implementing relevant port
3. Wire adapter to tinkex module

Output: Adapter code if needed


**Agent IMPL-3 - Documentation**:

Write module documentation:

1. @moduledoc with overview
2. @doc for each public function
3. Examples in docs

Output: Documentation strings


### 4.5 Verify Green (Tests Pass)

bash
mix test test/path/to/new_test.exs
# Should pass now


### 4.6 TDD Refactor Phase - Spawn Quality Agents (Parallel)

**Agent REF-1 - Code Quality**:

Review implementation for:
1. Code duplication - extract common patterns
2. Naming clarity - improve variable/function names
3. Module organization - split if too large
4. Remove dead code

Output: Refactoring suggestions with code


**Agent REF-2 - Dialyzer Check**:

Run dialyzer on new code:
1. mix dialyzer
2. Fix any type errors
3. Add missing @spec

Output: Dialyzer-clean code


**Agent REF-3 - Credo Check**:

Run credo on new code:
1. mix credo --strict
2. Fix all issues
3. Ensure consistent style

Output: Credo-clean code


### 4.7 Final Verification

Run full quality gate:

bash
mix compile --warnings-as-errors && mix test && mix dialyzer && mix credo --strict


---

## PHASE 5: ITERATION CHECKPOINT

### 5.1 Update Progress

After each implementation cycle:

1. Update CHECKLIST.md - mark completed items
2. Update GAP_ANALYSIS.md - remove closed gaps
3. Commit changes with descriptive message

### 5.2 Determine Next Iteration

If time/context remains:
- Return to PHASE 4.1 (Select Next Work Item)
- Continue TDD/RGR cycle

If ending session:
- Ensure all docs are updated
- Note any blockers or decisions needed
- Commit all changes

---

## MULTIAGENT PATTERNS REFERENCE

### Pattern 1: Parallel Exploration

Launch N agents simultaneously to explore different areas.
Wait for all to complete before synthesis.
Use for: Initial assessment, gap analysis, reading comprehension


### Pattern 2: Sequential Pipeline

Agent A output feeds Agent B input.
Use for: Test → Implement → Refactor flow


### Pattern 3: Competing Approaches

Launch multiple agents with same goal, different approaches.
Select best result.
Use for: Implementation alternatives, optimization


### Pattern 4: Hierarchical Delegation

Coordinator agent spawns worker agents.
Workers report back to coordinator.
Use for: Complex multi-file changes


### Pattern 5: Watchdog Pattern

One agent implements, another verifies.
Verification agent runs tests/checks.
Use for: Quality assurance


---

## AGENT SPAWN TEMPLATES

### Exploration Agent

Task: subagent_type=Explore
Prompt: 'Explore [PATH] to understand [GOAL]. Return [FORMAT].'


### Implementation Agent

Task: subagent_type=general-purpose
Prompt: 'Implement [MODULE]. Read [SOURCE]. Write to [TARGET]. Must pass [TESTS].'


### Verification Agent

Task: subagent_type=general-purpose
Prompt: 'Verify [CODE] by running [COMMANDS]. Report [METRICS].'


### Documentation Agent

Task: subagent_type=general-purpose
Prompt: 'Update [DOC_FILE] with [CONTENT]. Maintain [FORMAT].'


---

## INTEGRATION POINTS

### Pristine Core Usage
elixir
# Use pristine pipeline for HTTP requests
Pristine.Core.Pipeline.execute(context, endpoint, payload, opts)

# Use pristine types via Sinter
Sinter.Schema.define([...])
Sinter.Validator.validate(schema, data)


### Foundation Usage
elixir
# Retry with Foundation
Foundation.Retry.run(fn -> ... end, policy)

# Circuit breaker
Foundation.CircuitBreaker.call(breaker, fn -> ... end)

# Rate limiting
Foundation.RateLimit.BackoffWindow.should_backoff?(limiter)


### Sinter Usage
elixir
# Define types
schema = Sinter.Schema.define([
  {:field_name, :string, required: true}
])

# Validate
{:ok, validated} = Sinter.Validator.validate(schema, data)


### Multipart Usage
elixir
# Encode multipart
{content_type, body} = Multipart.encode(form_data)


### TelemetryReporter Usage
elixir
# Log events
TelemetryReporter.log(reporter, 'event.name', %{data: value}, :info)


---

## SUCCESS CRITERIA

Each iteration should:
1. Reduce gap count
2. Increase test coverage
3. Maintain zero warnings/errors
4. Update documentation

Port is complete when:
- All 67+ types ported
- All core clients functional
- All examples from source work in port
- Full test suite passing
- Zero dialyzer errors
- Zero credo issues

---

## NOTES FOR AGENTS

1. **Always read before writing** - Understand source before porting
2. **Prefer pristine infrastructure** - Use ports/adapters over direct implementation
3. **Maintain API parity** - Function signatures must match source
4. **Test first** - Never implement without failing tests
5. **Document as you go** - Keep gap analysis and checklist current
6. **Small commits** - Atomic, well-described changes
7. **Ask when stuck** - Use AskUserQuestion for blocking decisions

---

*Last updated: 2025-01-05*
*Version: 1.0.0*

