# Pristine Workspace

`pristine` is a tooling-root, non-umbrella Elixir monorepo. The repo root owns
workspace tooling, quality gates, and repo-level docs only. Publishable runtime
and code generation code lives in child apps.

## Workspace Apps

- `apps/pristine_runtime`
  The publishable `pristine` runtime package. This app owns request execution,
  Foundation-backed runtime wiring, OAuth helpers, and the
  `Pristine.Client` / `Pristine.Operation` contract.
- `apps/pristine_codegen`
  The publishable `pristine_codegen` package. This app owns the shared provider
  compiler, `PristineCodegen.ProviderIR`, bounded plugin contracts, renderer
  output, and the `pristine.codegen.*` task family.
- `apps/pristine_provider_testkit`
  Shared freshness and conformance helpers for downstream provider SDK repos.
  This app stays unpublished for now.

## Monorepo Commands

Run these from the repo root:

```bash
mix test
mix monorepo.deps.get
mix monorepo.format
mix monorepo.compile
mix monorepo.test
mix monorepo.credo --strict
mix monorepo.dialyzer
mix monorepo.docs
mix quality
mix docs.all
mix ci
```

`mix test` validates the root workspace contracts only. `mix ci` is the main
workspace acceptance gate.

## Shortcuts

The root `mix.exs` also defines `mr.*` aliases for the same monorepo task
surface:

```bash
mix mr.deps.get
mix mr.format
mix mr.compile
mix mr.test
mix mr.credo --strict
mix mr.dialyzer
mix mr.docs
```

These are shortcuts for the corresponding `mix monorepo.*` commands above.

## Blitz Workspace

The repo no longer carries its own monorepo runner implementation. Most
`monorepo.*` commands are root aliases to the generic
`mix blitz.workspace <task>` runner from the `blitz` Hex package.

`mix monorepo.dialyzer` is the exception: it runs once from the tooling root so
Dialyzer can analyze the shared `_build` outputs for all package apps inside one
consistent PLT/build context.

Workspace policy lives in the root `mix.exs` under `:blitz_workspace`:

- project discovery comes from `projects`
- task behavior comes from `tasks`
- concurrency weights come from `parallelism.base`
- machine scaling comes from `parallelism.multiplier: :auto`
- `PRISTINE_MONOREPO_MAX_CONCURRENCY` and `--max-concurrency N` override the
  current run directly

## Where To Start

- Runtime package docs: `apps/pristine_runtime/README.md`
- Codegen package docs: `apps/pristine_codegen/README.md`
- Provider testkit docs: `apps/pristine_provider_testkit/README.md`
- Workspace verification guide: `guides/testing-and-verification.md`
- Workspace examples index: `examples/index.md`
