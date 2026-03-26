# Testing And Verification

The root project owns workspace-wide verification. App-specific tests stay in
each package, while the root orchestrates shared quality gates.

## Root Commands

Run these from `/home/home/p/g/n/pristine`:

```bash
mix test
mix monorepo.deps.get
mix monorepo.format --check-formatted
mix monorepo.compile
mix monorepo.test
mix monorepo.credo --strict
mix monorepo.dialyzer
mix monorepo.docs
mix mr.format --check-formatted
mix mr.compile
mix mr.test
mix mr.credo --strict
mix mr.dialyzer
mix mr.docs
mix quality
mix docs.all
mix ci
```

`mix test` covers the root workspace contracts only. `mix ci` is the complete
workspace acceptance pass.

## Workspace Verification Model

Most `monorepo.*` aliases delegate to `mix blitz.workspace <task>`. Dialyzer is
the exception: it runs once from the repo root against the shared `_build`
outputs so the whole workspace is analyzed in one consistent PLT and build
context.

Use `mr.*` aliases for daily work. Use `monorepo.*` aliases when you want the
spelled-out task names.

To tune fan-out for a single run, pass `--max-concurrency N` to a
`mix monorepo.*` command. To set a default locally, export
`PRISTINE_MONOREPO_MAX_CONCURRENCY`.

## Package-Level Iteration

Use app-local commands when you are changing one package in isolation:

```bash
cd apps/pristine_runtime && mix test
cd apps/pristine_codegen && mix test
cd apps/pristine_provider_testkit && mix test
```

## Provider Repositories

Provider repositories should use the shared codegen and testkit entrypoints:

```bash
mix pristine.codegen.generate MyProvider.Provider --project-root .
mix pristine.codegen.verify MyProvider.Provider --project-root .
mix pristine.codegen.ir MyProvider.Provider --project-root .
mix pristine.codegen.refresh MyProvider.Provider --project-root .
```

Provider freshness and conformance assertions should use
`PristineProviderTestkit.Conformance.verify_provider/2` plus
`PristineProviderTestkit.Artifacts` for low-level file assertions.
