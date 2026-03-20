# Pristine Provider Testkit

`apps/pristine_provider_testkit` holds shared verification helpers for
downstream provider SDK repos.

The current shared surface is:

- `PristineProviderTestkit.Artifacts`
- `PristineProviderTestkit.Conformance`

Typical provider-repo usage is:

```elixir
assert :ok =
         PristineProviderTestkit.Conformance.verify_provider(
           MyProvider.Provider,
           project_root: File.cwd!()
         )
```

This app stays unpublished for now and is the workspace home for reusable
artifact freshness and provider conformance helpers.
