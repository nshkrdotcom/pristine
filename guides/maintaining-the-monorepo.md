# Maintaining The Monorepo

The repo root is the operational layer for development, docs, and quality
checks.

## Normal Development Loop

For a typical change:

1. work in the package that owns the change
2. run that package's local tests
3. run the relevant root `mr.*` checks
4. finish with `mix ci` before publishing or merging

## Docs Maintenance

Root HexDocs are the monorepo portal. Package HexDocs remain package-specific.

When adding a guide:

1. write the Markdown file under `guides/`
2. add it to the root `docs().extras`
3. place it in the correct `groups_for_extras` section
4. rebuild docs and verify the menu order

Use the same discipline inside package apps when a new guide belongs to a
publishable package instead of the workspace portal.

## Workspace Policy

The root `mix.exs` owns:

- Blitz workspace discovery
- shared aliases
- docs menu structure
- shared Dialyzer configuration
- root acceptance commands

That keeps monorepo policy centralized instead of duplicated across apps.
