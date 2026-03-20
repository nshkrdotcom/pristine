# Testing And Verification

The root project is responsible for workspace-wide checks. App-specific tests
stay inside each app; the root only verifies monorepo contracts.

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

`mix test` covers the root workspace contracts only. `mix ci` is the full
acceptance pass for the monorepo bootstrap.

Most root `monorepo.*` aliases delegate to `mix blitz.workspace <task>`. The
Dialyzer alias stays root-owned so one run can analyze the shared package beam
outputs without per-app build/deps isolation. Use the shorter `mr.*` aliases
for day-to-day work.

To tune workspace fan-out for one run, pass `--max-concurrency N` to a
`mix monorepo.*` command. To set a default locally, export
`PRISTINE_MONOREPO_MAX_CONCURRENCY`.

## App Boundaries

- `apps/pristine_runtime`
  Runtime execution, OAuth, streaming, adapters, and the direct
  `Pristine.Client` / `Pristine.Operation` runtime surface.
- `apps/pristine_codegen`
  Shared provider compiler, `ProviderIR` normalization, bounded plugins,
  generated source rendering, and shared Mix task coverage.
- `apps/pristine_provider_testkit`
  Shared artifact freshness and provider conformance helpers for downstream
  provider repos.

## Provider Verification

Provider repos should delegate generation through the shared task family:

```bash
mix pristine.codegen.generate MyProvider.Provider --project-root .
mix pristine.codegen.verify MyProvider.Provider --project-root .
mix pristine.codegen.ir MyProvider.Provider --project-root .
mix pristine.codegen.refresh MyProvider.Provider --project-root .
```

Provider freshness and conformance tests should use
`PristineProviderTestkit.Conformance.verify_provider/2` plus
`PristineProviderTestkit.Artifacts`.

## Package-Level Checks

Use app-local commands when you want to iterate on one package:

```bash
cd apps/pristine_runtime && mix test
cd apps/pristine_codegen && mix test
cd apps/pristine_provider_testkit && mix test
```

The runtime and codegen apps still own their own docs generation. Workspace
Dialyzer runs once from the root against the shared compiled package outputs.
