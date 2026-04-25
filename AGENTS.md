# Repository Guidelines

## Project Structure
- Root `mix.exs` coordinates the Pristine monorepo.
- `apps/pristine_runtime` is the publishable semantic HTTP runtime package.
- `apps/pristine_codegen` and `apps/pristine_provider_testkit` are tooling/test packages.
- Generated `doc/` output should not be edited.

## Execution Plane Stack
- `pristine` is the semantic HTTP family kit above `execution_plane`; it may carry mapped execution-plane contracts but must not expose raw lower HTTP package surfaces as its product API.
- Keep `execution_plane` dependency resolution publish-aware in publishable app
  manifests.
- In local sibling mode, `apps/pristine_runtime` resolves `:execution_plane`
  through `execution_plane_workspace_dep_path("core/execution_plane")` and
  `:execution_plane_http` through
  `execution_plane_workspace_dep_path("protocols/execution_plane_http")`.
  Do not point `:execution_plane` at the sibling repo root; that root is the
  non-published Blitz workspace project.
- `github_ex` and `notion_sdk` are the active proof SDKs for this layer.

## Gates
- Prefer root `mix ci` when present.
- Otherwise run the monorepo aliases advertised by the repo: format, compile, test, Credo, Dialyzer, and docs.
- For publishable apps, also verify `mix hex.build --unpack` from the app directory.
