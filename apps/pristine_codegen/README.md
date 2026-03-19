# Pristine Codegen

`apps/pristine_codegen` is the publishable `pristine_codegen` package.

This app owns the current build-time OpenAPI bridge:

- `Pristine.OpenAPI.Bridge`
- `Pristine.OpenAPI.Profile`
- `Pristine.OpenAPI.Result`
- `Pristine.OpenAPI.IR`
- `Pristine.OpenAPI.Renderer`

## Example

```elixir
result =
  Pristine.OpenAPI.Bridge.run(
    :widgets_sdk,
    ["openapi/widgets.json"],
    base_module: WidgetsSDK,
    output_dir: "lib/widgets_sdk/generated"
  )

sources = Pristine.OpenAPI.Bridge.generated_sources(result)
```

The codegen package depends on `pristine_runtime` as a path/package dependency
because generated sources and bridge profiles target the runtime package's
current public SDK surface.

## Guide

- `guides/code-generation.md`

## Workspace

Workspace-wide quality commands run from the repo root:

```bash
mix mr.compile
mix mr.test
mix ci
```
