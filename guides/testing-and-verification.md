# Testing And Verification

The root project is responsible for workspace-wide checks. App-specific tests
stay inside each app; the root only verifies monorepo contracts.

## Root Commands

Run these from `/home/home/p/g/n/pristine`:

```bash
mix mr.format --check-formatted
mix mr.compile
mix mr.test
mix mr.credo --strict
mix mr.dialyzer
mix mr.docs
mix ci
```

`mix ci` is the full acceptance pass for the monorepo bootstrap.

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

The runtime and codegen apps each own their own docs generation and dialyzer
state through the workspace aliases above.
