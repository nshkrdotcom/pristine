# Pristine Monorepo

This repository is the GitHub home for three related Elixir projects:

- `pristine`
  The runtime package published to Hex from `apps/pristine_runtime`.
- `pristine_codegen`
  The shared provider compiler in `apps/pristine_codegen`. This stays GitHub
  sourced.
- `pristine_provider_testkit`
  The downstream provider verification helper in
  `apps/pristine_provider_testkit`. This also stays GitHub sourced.

The repo root is not itself a publishable package. It is the monorepo control
plane for docs, workspace tooling, and shared quality gates.

## Which Dependency Goes Where

Use Hex for the runtime:

```elixir
{:pristine, "~> 0.2.0"}
```

Use GitHub `subdir:` dependencies for the build-time and test-time packages:

```elixir
{:pristine_codegen,
 github: "nshkrdotcom/pristine",
 branch: "master",
 subdir: "apps/pristine_codegen"}

{:pristine_provider_testkit,
 github: "nshkrdotcom/pristine",
 branch: "master",
 subdir: "apps/pristine_provider_testkit",
 only: :test}
```

For active local development across sibling checkouts, prefer path deps:

```elixir
{:pristine, path: "../pristine/apps/pristine_runtime"}
{:pristine_codegen, path: "../pristine/apps/pristine_codegen"}
{:pristine_provider_testkit,
 path: "../pristine/apps/pristine_provider_testkit", only: :test}
```

## Project Map

`apps/pristine_runtime`

The published `pristine` runtime. It owns request execution, adapters, OAuth,
streaming, `Pristine.Client`, `Pristine.Operation`, and the SDK-facing
`Pristine.foundation_context/1` plus `Pristine.execute_request/3` boundary.

`apps/pristine_codegen`

The shared provider compiler. It owns `PristineCodegen.Provider`,
`PristineCodegen.ProviderIR`, renderer output, artifact verification, and the
`mix pristine.codegen.*` tasks used by downstream SDK repos.

`apps/pristine_provider_testkit`

The provider-repo test helper layer. It wraps shared freshness and conformance
checks so downstream SDK repos can verify generated artifacts without copying
test infrastructure.

## Read Me First

- Runtime package: `apps/pristine_runtime/README.md`
- Codegen package: `apps/pristine_codegen/README.md`
- Provider testkit: `apps/pristine_provider_testkit/README.md`
- Workspace overview: `guides/workspace-overview.md`
- Getting started: `guides/getting-started.md`
- Runtime usage: `guides/runtime-and-sdk-usage.md`
- Code generation: `guides/code-generation-and-artifacts.md`

## Workspace Commands

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
mix mr.compile
mix mr.test
mix quality
mix docs.all
mix ci
```

`mix test` validates the root workspace contracts only. `mix ci` is the full
workspace acceptance gate.

When you need the underlying workspace runner directly, use
`mix blitz.workspace <task>`.

## License

This repository is released under the MIT License. The root workspace keeps the
canonical copy in `LICENSE.md`. The published `pristine` package also carries a
duplicate `LICENSE.md` inside `apps/pristine_runtime` so Hex users see the same
license text from the packaged app.
