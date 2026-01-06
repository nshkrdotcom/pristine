# Salvage Assessment - 2026-01-06

## TL;DR

**Keep pristine core (4,686 lines). Delete examples/tinkex (22,357 lines). Refactor original tinkex to use pristine.**

---

## Documents

| File | Purpose |
|------|---------|
| [SALVAGE_ASSESSMENT.md](./SALVAGE_ASSESSMENT.md) | What's worth keeping vs discarding |
| [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) | 6-phase migration plan |
| [PRISTINE_INVENTORY.md](./PRISTINE_INVENTORY.md) | Detailed module catalog |

---

## Key Findings

### Pristine Core: VALUABLE

```
lib/pristine/
├── core/           # Pipeline, context, request/response (860 lines)
├── ports/          # 12 interface contracts (150 lines)
├── adapters/       # 20+ implementations (1,543 lines)
├── codegen/        # SDK generation (1,663 lines)
├── streaming/      # SSE support (311 lines)
├── manifest/       # API definition loading (640 lines)
└── error.ex        # Error classification (227 lines)
```

- Hexagonal architecture properly implemented
- Code generation is production-quality
- 354 tests all pass
- Foundation integration works

### Examples/Tinkex: WORTHLESS

```
examples/tinkex/
└── lib/            # 22,357 lines of hand-written code
                    # Only 1 module imports pristine
                    # Duplicates all infrastructure
```

- Doesn't use pristine at all (except SSE decoder)
- Has handwritten retry, rate limiting, telemetry, serialization
- Generated code exists but unused
- Defeats the entire purpose

---

## Recommended Action

### Phase 0: Cleanup
```bash
rm -rf examples/tinkex
```

### Phase 1: Extend Pristine
Add missing ports: BytesSemaphore, Compression, Session, Environment

### Phase 2-3: Refactor Original Tinkex
Work in `~/p/g/North-Shore-AI/tinkex`:
- Add foundation dependency
- Replace custom infrastructure with foundation
- Refactor to hexagonal

### Phase 4-5: Integrate with Pristine
- Create manifest.json for full API surface
- Generate SDK code with pristine
- Wire tinkex to use generated code

### Phase 6: Cleanup
Remove duplicated infrastructure from tinkex.

---

## Target State

**Pristine**: ~8,000 lines of generalized SDK infrastructure
**Tinkex**: ~4,500 lines (manifest + domain logic + generated code)

vs current state where both have massive code duplication.

---

## Next Step

Start with the plan in `~/p/g/North-Shore-AI/tinkex/docs/20260106/hexagonal-refactor/` to refactor the original tinkex first.
