# Architecture And Package Boundaries

The monorepo is intentionally split by lifecycle:

- runtime concerns live in `apps/pristine_runtime`
- build-time compiler concerns live in `apps/pristine_codegen`
- downstream provider verification helpers live in
  `apps/pristine_provider_testkit`
- workspace orchestration and docs live at the repo root

## Runtime Boundary

`pristine` owns request execution and the adapter model.

Its public center of gravity is:

- `Pristine.Client`
- `Pristine.Operation`
- `Pristine.execute/3`
- `Pristine.execute_request/3`
- `Pristine.stream/3`
- `Pristine.OAuth2`
- `Pristine.SDK.OpenAPI.Client`

Internally, request execution is coordinated by `Pristine.Core.Pipeline` and a
`Pristine.Core.Context` that carries transport, serialization, resilience, and
telemetry dependencies.

## Compiler Boundary

`pristine_codegen` owns provider definition loading, plugin execution,
normalization into `PristineCodegen.ProviderIR`, source rendering, and artifact
verification.

Its center of gravity is:

- `PristineCodegen.Provider`
- `PristineCodegen.ProviderIR`
- `PristineCodegen.Compiler`
- `PristineCodegen.Render.ElixirSDK`
- `mix pristine.codegen.*`

The compiler is intentionally build-time only. It emits code and metadata that
the runtime consumes later.

## Provider Testkit Boundary

`pristine_provider_testkit` is intentionally narrow. It does not compile
providers independently. It reuses the compiler contract to give downstream
provider repositories a stable freshness and conformance surface.

## Why The Split Matters

This separation keeps runtime releases focused, keeps build-time code isolated,
and prevents provider repositories from drifting into bespoke generation rules
that diverge from the shared compiler.

## Consumption And Packaging

This repo is a non-umbrella workspace. The package boundaries are the child
apps, not the tooling root.

That means downstream repos should:

- consume `:pristine` from Hex
- consume `apps/pristine_codegen` as GitHub `subdir:` or sibling `path:`
- consume `apps/pristine_provider_testkit` as GitHub `subdir:` or sibling
  `path:` for test-only verification support

For local development, sibling-relative `path:` dependencies are the preferred
shape for all three child apps. Outside the local workspace, the intended split
is Hex for `:pristine` and GitHub `subdir:` dependencies for the other two.

Do not build connector or SDK repos around committed vendored `deps/pristine`
layouts. One OTP app should have one origin within a given dependency graph.
