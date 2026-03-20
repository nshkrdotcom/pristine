# Code Generation

`PristineCodegen` is the shared provider compiler for generated SDK repos.

The compiler accepts:

- one provider definition module implementing `PristineCodegen.Provider`
- zero or more bounded plugins for source, auth, pagination, and docs/example
  enrichment
- committed provider inputs and fingerprints

The compiler emits:

- canonical `PristineCodegen.ProviderIR`
- generated provider client, operation, pagination, and type modules
- committed provider artifacts such as `provider_ir.json`,
  `generation_manifest.json`, and `docs_inventory.json`

## Provider Contract

Every provider repo should define:

- `definition/1`
- `paths/1`
- `source_plugins/0`
- `auth_plugins/0`
- `pagination_plugins/0`
- `docs_plugins/0`
- optional `refresh/1`

Source plugins return `PristineCodegen.Source.Dataset`. Auth, pagination, and
docs plugins receive `PristineCodegen.ProviderIR` and must return
`PristineCodegen.ProviderIR`.

## Running The Compiler

```elixir
{:ok, compilation} =
  PristineCodegen.generate(MyProvider.Provider, project_root: File.cwd!())

provider_ir = compilation.provider_ir
```

Provider repos should expose provider-facing tasks that delegate into the shared
task family:

```bash
mix pristine.codegen.generate MyProvider.Provider --project-root .
mix pristine.codegen.verify MyProvider.Provider --project-root .
mix pristine.codegen.ir MyProvider.Provider --project-root .
mix pristine.codegen.refresh MyProvider.Provider --project-root .
```

## Runtime Contract

Generated provider code targets the runtime package directly:

- `Pristine.Client`
- `Pristine.Operation`
- `Pristine.execute/3`
- `Pristine.stream/3`

Generated operation modules construct `Pristine.Operation` values from
`ProviderIR`, partition request params with `Pristine.Operation.partition/2`,
and execute through `Pristine.execute/3` or generated pagination wrappers over
that contract. They do not emit request-spec maps, bridge state, or repo-local
generic execution shims.
