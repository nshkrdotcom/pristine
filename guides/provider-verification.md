# Provider Verification

Downstream provider repositories should verify freshness and conformance through
the shared compiler contract instead of inventing local rules.

## Shared Testkit Surface

The provider testkit exposes two small helpers:

- `PristineProviderTestkit.Conformance`
- `PristineProviderTestkit.Artifacts`

The main entrypoint is:

```elixir
assert :ok =
         PristineProviderTestkit.Conformance.verify_provider(
           MyProvider.Provider,
           project_root: File.cwd!()
         )
```

## What Verification Means

Conformance verification delegates to `PristineCodegen.verify/2`. A provider
passes when:

- every expected generated file exists
- every committed generated file matches the compiler output
- no forbidden legacy outputs are still present

If you want a task that updates files in place, the same helper supports
`write?: true`, which delegates to generation instead of read-only verification.

## Suggested Provider CI Pattern

Run provider refresh or generation in the repository that owns the provider
definition, then fail CI on any stale generated output:

```bash
mix pristine.codegen.verify MyProvider.Provider --project-root .
```

This keeps generation policy centralized in `pristine_codegen` while letting
provider repositories retain committed artifacts and docs inventories.
