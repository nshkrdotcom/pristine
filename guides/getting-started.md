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
