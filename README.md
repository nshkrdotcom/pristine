# Pristine Workspace

`pristine` is a tooling-root, non-umbrella Elixir monorepo for a generated SDK
stack. The repo root owns workspace tooling, shared quality gates, and the
monorepo-level guides. Publishable runtime and compiler code lives in child
apps.

## Package Map

- `apps/pristine_runtime`
  The publishable `pristine` runtime package. It owns request execution,
  Foundation-backed runtime wiring, OAuth helpers, the classic
  `Pristine.Client` / `Pristine.Operation` contract, and the SDK-facing
  `Pristine.foundation_context/1` / `Pristine.execute_request/3` boundary used
  by generated provider SDKs.
- `apps/pristine_codegen`
  The publishable `pristine_codegen` package. This app owns the shared provider
  compiler, `PristineCodegen.ProviderIR`, bounded plugin contracts, renderer
  output, and the `pristine.codegen.*` task family.
- `apps/pristine_provider_testkit`
  Shared freshness and conformance helpers for downstream provider SDK repos.
  This app stays unpublished for now.

## Consumption Model

Downstream repos should consume the child apps directly. Do not depend on the
workspace root as a runtime package, and do not vendor a second copy of
`pristine` into committed `deps/`.

For active local development, prefer sibling-relative path dependencies:

```elixir
{:pristine, path: "../pristine/apps/pristine_runtime"}
{:pristine_codegen, path: "../pristine/apps/pristine_codegen"}
{:pristine_provider_testkit,
 path: "../pristine/apps/pristine_provider_testkit", only: :test}
```

If the sibling checkout is not available, use a pinned git ref with `subdir:`
for each child app:

```elixir
{:pristine,
 github: "nshkrdotcom/pristine",
 ref: "<pinned-commit-sha>",
 subdir: "apps/pristine_runtime"}

{:pristine_codegen,
 github: "nshkrdotcom/pristine",
 ref: "<pinned-commit-sha>",
 subdir: "apps/pristine_codegen"}

{:pristine_provider_testkit,
 github: "nshkrdotcom/pristine",
 ref: "<pinned-commit-sha>",
 subdir: "apps/pristine_provider_testkit",
 only: :test}
```

`subdir:` is intentional. The child apps share workspace-local `_build`,
`deps`, and `mix.lock` paths, so full checkout plus `subdir:` is the stable
fallback shape.

## Start Here

The root HexDocs are organized into three tracks:

- project documents: `README`, `CHANGELOG`, and `LICENSE`
- user guides: workspace overview, getting started, runtime usage, code
  generation, provider verification, and testing
- developer guides: architecture, runtime internals, codegen internals, and
  monorepo maintenance

If you are adopting the stack:

- start with `guides/workspace-overview.md`
- move to `guides/getting-started.md`
- then choose `guides/runtime-and-sdk-usage.md` or
  `guides/code-generation-and-artifacts.md`

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

## Shortcut Aliases

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

## Workspace Runner

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

## Package Docs

- Runtime package docs: `apps/pristine_runtime/README.md`
- Codegen package docs: `apps/pristine_codegen/README.md`
- Provider testkit docs: `apps/pristine_provider_testkit/README.md`
- Workspace overview: `guides/workspace-overview.md`
- Workspace verification guide: `guides/testing-and-verification.md`
- Workspace examples index: `examples/index.md`
