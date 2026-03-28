# Workspace Overview

Pristine is split into three distinct responsibilities:

- `pristine`
  Runtime execution, adapters, OAuth helpers, request/response handling, and
  the SDK-facing execution boundary.
- `pristine_codegen`
  Build-time provider compilation, canonical `ProviderIR`, renderer output, and
  committed artifact generation or freshness verification.
- `pristine_provider_testkit`
  Small downstream-provider helpers that reuse the shared codegen verification
  contract inside provider repositories.

The root project is not the product runtime. It is the monorepo entrypoint for
tooling, verification, and docs.

## Consumption Boundary

Consumer repos should depend on the child packages directly. The root workspace
is for local tooling, verification, and docs only.

The intended downstream pattern is:

- Hex for `:pristine`
- GitHub `subdir:` dependencies for `:pristine_codegen` and
  `:pristine_provider_testkit`
- sibling-relative `path:` dependencies for active local development

The workspace should not be re-vendored inside another repo's committed
`deps/` directory. That creates a second origin for the same OTP apps and makes
consumer behavior diverge from local workspace behavior.

## Who Uses What

Use the runtime package when you need to execute requests or build SDK clients.

Use the codegen package when you own a provider repository and need to compile
OpenAPI-derived definitions into generated Elixir code and committed metadata.

Use the provider testkit when a downstream provider repository wants a thin,
shared verification layer without duplicating artifact freshness logic.

## Key Boundaries

- The runtime accepts either `Pristine.Client` plus `Pristine.Operation`, or a
  request-spec map executed through `Pristine.execute_request/3`.
- The code generator emits code and artifacts that target the runtime package
  directly.
- The provider testkit depends on the compiler contract instead of reimplementing
  generation logic.

## Recommended Reading Order

1. Read [Getting Started](getting-started.md).
2. Read [Runtime And SDK Usage](runtime-and-sdk-usage.md) if you are integrating
   the execution layer.
3. Read [Code Generation And Artifacts](code-generation-and-artifacts.md) if you
   are building or maintaining a provider SDK.
4. Read [Provider Verification](provider-verification.md) and
   [Testing And Verification](testing-and-verification.md) before automating CI.
