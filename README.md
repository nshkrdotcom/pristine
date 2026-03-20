# Pristine Workspace

`pristine` is now a non-umbrella monorepo. The root project is tooling only and
exists to run workspace-wide formatting, compilation, testing, docs, credo, and
dialyzer checks.

## Workspace Apps

- `apps/pristine_runtime`
  The publishable runtime package. This app ships the `pristine` package and
  owns request execution, Foundation-backed runtime wiring, OAuth helpers, and
  the `Pristine.Client` / `Pristine.Operation` runtime contract.
- `apps/pristine_codegen`
  The publishable build-time package. This app owns the shared provider
  compiler, `PristineCodegen.ProviderIR`, bounded plugin contracts, renderer
  output, and the shared `pristine.codegen.*` task family.
- `apps/pristine_provider_testkit`
  Shared freshness and conformance helpers for downstream provider SDK repos.
  This app stays unpublished for now.

## Workspace Commands

Run all cross-workspace quality checks from the repo root:

```bash
mix mr.format --check-formatted
mix mr.compile
mix mr.test
mix mr.credo --strict
mix mr.dialyzer
mix mr.docs
mix ci
```

The root project wires these commands through in-tree `monorepo.*` tasks in the
same non-umbrella monorepo style used by `jido_integration`.

## Where To Start

- Runtime package docs: `apps/pristine_runtime/README.md`
- Codegen package docs: `apps/pristine_codegen/README.md`
- Provider testkit docs: `apps/pristine_provider_testkit/README.md`
- Workspace verification guide: `guides/testing-and-verification.md`
- Workspace examples index: `examples/index.md`
