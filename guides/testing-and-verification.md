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
  Runtime execution, OAuth, streaming, adapters, and the current SDK-facing
  runtime surface.
- `apps/pristine_codegen`
  OpenAPI bridge/profile/result/IR/renderer modules and the current build-time
  generation tests.
- `apps/pristine_provider_testkit`
  Shared verification helpers for downstream provider repos.

## Package-Level Checks

Use app-local commands when you want to iterate on one package:

```bash
cd apps/pristine_runtime && mix test
cd apps/pristine_codegen && mix test
cd apps/pristine_provider_testkit && mix test
```

The runtime and codegen apps each own their own docs generation and dialyzer
state through the workspace aliases above.
