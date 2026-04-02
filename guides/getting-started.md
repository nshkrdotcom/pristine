# Getting Started

This monorepo is optimized for two workflows:

- consuming the runtime directly
- maintaining generated provider SDKs on top of the shared compiler

## Prerequisites

- Elixir `~> 1.18`
- Erlang/OTP compatible with the project toolchain
- a clean clone with root access to run shared `mix` tasks

Fetch dependencies from the repo root:

```bash
mix monorepo.deps.get
```

## Consuming Child Apps

`pristine` is a workspace, not a single runtime package. Downstream projects
should consume the child apps they need:

- `:pristine` from Hex for runtime use
- `apps/pristine_codegen` from GitHub `subdir:` or a sibling `path:`
- `apps/pristine_provider_testkit` from GitHub `subdir:` or a sibling `path:`
  when provider-repo tests need the shared verification helpers

For a normal runtime dependency, use:

```elixir
{:pristine, "~> 0.2.1"}
```

For local development beside this repo, use sibling-relative paths:

```elixir
{:pristine, path: "../pristine/apps/pristine_runtime"}
{:pristine_codegen, path: "../pristine/apps/pristine_codegen"}
```

If the sibling checkout is absent, keep `:pristine` on Hex and use GitHub
`subdir:` dependencies for the build-time packages instead of introducing
vendored `deps/*` copies.

## Common Workspace Commands

The repo root is the control plane for workspace checks:

```bash
mix mr.compile
mix mr.test
mix mr.credo --strict
mix mr.dialyzer
mix mr.docs
mix ci
```

`mix test` only covers root workspace contracts. Use `mix ci` for the full
acceptance gate.

## Choose Your Entry Point

If you are integrating the runtime manually, start in
`apps/pristine_runtime` and use `Pristine.foundation_context/1` or
`Pristine.Client.foundation/1`.

If you are building generated providers, start in `apps/pristine_codegen` and
implement `PristineCodegen.Provider`.

If you are validating a downstream provider repository, use
`PristineProviderTestkit.Conformance.verify_provider/2`.

## Useful Next Steps

- [Runtime And SDK Usage](runtime-and-sdk-usage.md)
- [Code Generation And Artifacts](code-generation-and-artifacts.md)
- [Testing And Verification](testing-and-verification.md)
