# Pristine Workspace

`pristine` is now a non-umbrella monorepo. The root project is tooling only and
exists to run workspace-wide formatting, compilation, testing, docs, credo, and
dialyzer checks.

## Workspace Apps

- `apps/pristine_runtime`
  The publishable runtime package. This app still ships the `pristine` package
  and owns request execution, Foundation-backed runtime wiring, OAuth helpers,
  streaming, and the current SDK-facing runtime modules.
- `apps/pristine_codegen`
  The publishable build-time package. This app owns the retained
  `Pristine.OpenAPI.Bridge.run/3` seam, OpenAPI normalization, rendering, and
  generated docs/artifact support.
- `apps/pristine_provider_testkit`
  Shared verification helpers for downstream provider SDK repos. This app stays
  unpublished for now.

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
