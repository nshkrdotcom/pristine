# Pristine Codegen

`apps/pristine_codegen` is the shared provider compiler for downstream SDK
repositories.

This package is intended to stay GitHub sourced rather than Hex published.

Use it with the published `pristine` runtime on Hex:

```elixir
{:pristine, "~> 0.2.0"}
{:pristine_codegen,
 github: "nshkrdotcom/pristine",
 branch: "master",
 subdir: "apps/pristine_codegen"}
```

For local development across sibling repos, prefer:

```elixir
{:pristine_codegen, path: "../pristine/apps/pristine_codegen"}
```

This app owns the shared provider compiler:

- `PristineCodegen.Provider`
- `PristineCodegen.ProviderIR`
- `PristineCodegen.Compiler`
- `PristineCodegen.Render.ElixirSDK`
- `mix pristine.codegen.generate <ProviderModule>`
- `mix pristine.codegen.verify <ProviderModule>`
- `mix pristine.codegen.ir <ProviderModule>`
- `mix pristine.codegen.refresh <ProviderModule>`

## Example

```elixir
defmodule WidgetAPI.Provider do
  @behaviour PristineCodegen.Provider

  def definition(_opts) do
    %{
      provider: %{
        id: :widget_api,
        base_module: WidgetAPI,
        package_app: :widget_api,
        package_name: "widget_api",
        source_strategy: :openapi_only
      },
      runtime_defaults: %{
        base_url: "https://api.example.com",
        default_headers: %{"accept" => "application/json"},
        user_agent_prefix: "WidgetAPI",
        timeout_ms: 15_000,
        retry_defaults: %{strategy: :standard},
        serializer: :json,
        typed_responses_default: true
      },
      operations: [],
      schemas: [],
      auth_policies: [],
      pagination_policies: [],
      docs_inventory: %{guides: [], examples: [], operations: %{}},
      fingerprints: %{sources: [], generation: %{compiler: "pristine_codegen"}},
      artifact_plan: %{
        generated_code_dir: "lib/widget_api/generated",
        artifacts: [
          %{id: :provider_ir, path: "priv/generated/provider_ir.json"},
          %{id: :generation_manifest, path: "priv/generated/generation_manifest.json"},
          %{id: :docs_inventory, path: "priv/generated/docs_inventory.json"}
        ],
        forbidden_paths: []
      }
    }
  end

  def paths(opts) do
    project_root = Keyword.fetch!(opts, :project_root)

    %{
      project_root: project_root,
      generated_code_dir: Path.join(project_root, "lib/widget_api/generated"),
      generated_artifact_dir: Path.join(project_root, "priv/generated")
    }
  end

  def source_plugins, do: []
  def auth_plugins, do: []
  def pagination_plugins, do: []
  def docs_plugins, do: []
end

{:ok, compilation} =
  PristineCodegen.generate(WidgetAPI.Provider, project_root: File.cwd!())

compilation.provider_ir
```

Generated provider modules target the published `pristine` runtime directly:

- `Pristine.Client`
- `Pristine.Operation`
- `Pristine.execute/3`
- `Pristine.stream/3`

Providers may also declare repo-specific committed artifacts in
`artifact_plan.artifacts` and implement `render_artifact/4`. The shared
compiler normalizes those artifact contents before writing and freshness
verification, so provider hooks can return normal binaries or iodata.

## Scope

This README is intentionally specific to the compiler. For the monorepo layout
and package-publishing policy, start at the GitHub root `README.md`.

## Guide

- `guides/code-generation.md`

## Workspace

Workspace-wide quality commands run from the repo root:

```bash
mix mr.compile
mix mr.test
mix ci
```
