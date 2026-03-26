# Codegen Internals

The code generator is a compiler pipeline, not a code template dump.

## Compiler Stages

`PristineCodegen.Compiler` runs provider compilation in a fixed order:

1. read the provider definition from `PristineCodegen.Provider`
2. collect source-plugin datasets
3. normalize the merged definition into canonical provider IR
4. apply auth, pagination, and docs plugins over `PristineCodegen.ProviderIR`
5. render source files with `PristineCodegen.Render.ElixirSDK`
6. render committed artifacts from the final compilation output

Each stage returns structured data rather than mutating global state. That keeps
verification deterministic and allows the same pipeline to power `compile`,
`generate`, `verify`, `emit_ir`, and `refresh`.

## Why ProviderIR Exists

`PristineCodegen.ProviderIR` is the canonical build-time contract between
provider inputs and rendered outputs. It stores:

- provider identity and naming
- runtime defaults
- operations and schemas
- auth and pagination policies
- docs inventory
- artifact plan
- fingerprints

Because the renderer consumes normalized IR, source plugins and docs plugins can
remain narrow and focused instead of each reimplementing format-specific logic.

## Artifact Verification

The artifact layer computes the final generated file set, writes files when
generation is requested, and supports the freshness checks used by
`PristineCodegen.verify/2`.

That verification model is central to the architecture. Generated files are
part of the provider contract and are expected to be reviewable, committable,
and reproducible.
