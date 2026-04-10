# Pristine Provider Testkit

`apps/pristine_provider_testkit` holds shared verification helpers for
downstream provider SDK repos.

This package is test-only infrastructure and is intended to stay GitHub
sourced.

Use it alongside Hex `pristine` and GitHub `pristine_codegen`:

```elixir
{:pristine, "~> 0.2.0"}
{:pristine_codegen,
 github: "nshkrdotcom/pristine",
 branch: "main",
 subdir: "apps/pristine_codegen"}
{:pristine_provider_testkit,
 github: "nshkrdotcom/pristine",
 branch: "main",
 subdir: "apps/pristine_provider_testkit",
 only: :test}
```

For local development, the expected shape is:

```elixir
{:pristine_provider_testkit,
 path: "../pristine/apps/pristine_provider_testkit",
 only: :test}
```

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
