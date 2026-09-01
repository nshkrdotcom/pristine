# Repository Guidelines

## Project Structure
- Root `mix.exs` coordinates the Pristine monorepo.
- `apps/pristine_runtime` is the publishable semantic HTTP runtime package.
- `apps/pristine_codegen` and `apps/pristine_provider_testkit` are tooling/test packages.
- Generated `doc/` output should not be edited.

## Execution Plane Stack
- `pristine` is the semantic HTTP family kit above `execution_plane`; it may carry mapped execution-plane contracts but must not expose raw lower HTTP package surfaces as its product API.
- Cross-repository source substitution uses MWO's tuple-first
  `workspace_dep(committed_tuple)` seam. Committed tuples are standalone Hex defaults;
  MWO activation substitutes only source coordinates.
- Machine-local source preferences belong in MWO's XDG operator state. Do not install a
  repository-local dependency-source helper or override file.
- Dependency source selection must not use environment variables.
- In local sibling mode, `apps/pristine_runtime` resolves `:execution_plane` to
  `../execution_plane/core/execution_plane` and `:execution_plane_http` to
  `../execution_plane/protocols/execution_plane_http`. Do not point
  `:execution_plane` at the sibling repo root; that root is the non-published
  Blitz workspace project.
- `github_ex` and `notion_sdk` are the active proof SDKs for this layer.
- Runtime application code under `lib/**` must not call direct OS env APIs such
  as `System.get_env/1`, `System.fetch_env/1`, `System.fetch_env!/1`,
  `System.put_env/2`, `System.delete_env/1`, or `System.get_env/0`.
- Runtime env reads belong in `config/runtime.exs` or a `Config.Provider`;
  library APIs should receive explicit options or materialized application
  config.
- Pristine is not in the Weld consumer set. Do not add a Weld dependency, Weld
  task, or Weld Credo check as part of Phase 2 cleanup.

## Gates
- Prefer root `mix ci` when present.
- Otherwise run the monorepo aliases advertised by the repo: format, compile, test, Credo, Dialyzer, and docs.
- For publishable apps, also verify `mix hex.build --unpack` from the app directory.

## Blitz 0.3.0 operational note

Root workspace Blitz uses published Hex `~> 0.3.0` by default; `.blitz/` is committed compact impact state after green QC. Source and `mix.exs` changes cascade through reverse workspace dependencies; docs-only changes should stay owner-local.
