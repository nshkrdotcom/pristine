# Code Generation And Artifacts

`pristine_codegen` turns a provider definition into two outputs:

- generated Elixir source files
- committed machine-readable artifacts such as `provider_ir.json`,
  `generation_manifest.json`, and `docs_inventory.json`

## Provider Contract

A provider repository implements `PristineCodegen.Provider` and supplies:

- `definition/1`
- `paths/1`
- `source_plugins/0`
- `auth_plugins/0`
- `pagination_plugins/0`
- `docs_plugins/0`

`refresh/1` and `render_artifact/4` are optional extension points.

## Compiler Flow

The shared compiler executes the provider definition in a stable sequence:

1. Load the base provider definition.
2. Merge data from source plugins as `PristineCodegen.Source.Dataset`.
3. Normalize the result into canonical `PristineCodegen.ProviderIR`.
4. Apply auth, pagination, and docs plugins over the IR.
5. Render generated source files.
6. Render built-in and provider-defined committed artifacts.

That flow is exposed through:

```elixir
PristineCodegen.compile/2
PristineCodegen.generate/2
PristineCodegen.verify/2
PristineCodegen.emit_ir/2
PristineCodegen.refresh/2
```

## Task Surface

Provider repositories are expected to delegate to the shared Mix tasks:

```bash
mix pristine.codegen.generate MyProvider.Provider --project-root .
mix pristine.codegen.verify MyProvider.Provider --project-root .
mix pristine.codegen.ir MyProvider.Provider --project-root .
mix pristine.codegen.refresh MyProvider.Provider --project-root .
```

## Artifact Discipline

The compiler treats artifacts as part of the provider contract, not as
incidental build output. Verification checks for:

- missing generated files
- stale committed files whose contents no longer match compiler output
- forbidden legacy paths declared in the provider artifact plan

This is why provider repos can keep generated files committed while still
enforcing freshness deterministically in CI.

## Where To Go Deeper

- codegen package overview: `apps/pristine_codegen/README.md`
- codegen package guide: `apps/pristine_codegen/guides/code-generation.md`
- [Codegen Internals](codegen-internals.md)
