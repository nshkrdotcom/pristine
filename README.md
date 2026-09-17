<p align="center">
  <img src="assets/pristine.svg" width="200" height="200" alt="Pristine logo" />
</p>

<h1 align="center">Pristine</h1>

<p align="center">
  <strong>Semantic HTTP client runtime and code generation toolkit for Elixir</strong>
</p>

<p align="center">
  <a href="https://hex.pm/packages/pristine"><img src="https://img.shields.io/hexpm/v/pristine.svg" alt="Hex Version" /></a>
  <a href="https://hexdocs.pm/pristine"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="Hex Docs" /></a>
  <a href="https://github.com/nshkrdotcom/pristine"><img src="https://img.shields.io/badge/GitHub-repo-black?logo=github" alt="GitHub" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License" /></a>
</p>

---

Pristine is a modular Elixir monorepo for building and running resilient, type-safe HTTP clients and OpenAPI-driven SDKs. Built on a clean Ports and Adapters architecture, Pristine separates high-level domain semantics from low-level transport and execution mechanics.

The repository root serves as the monorepo control plane for documentation, workspace tooling, and unified quality gates.

## Monorepo Packages

| Package | Location | Distribution | Role |
|:---|:---|:---|:---|
| **`pristine`** | [`apps/pristine_runtime`](https://github.com/nshkrdotcom/pristine/tree/main/apps/pristine_runtime) | [Hex.pm](https://hex.pm/packages/pristine) (`~> 0.4.0`) | Semantic HTTP runtime, request pipelines, OAuth2, streaming, and resilience |
| **`pristine_codegen`** | [`apps/pristine_codegen`](https://github.com/nshkrdotcom/pristine/tree/main/apps/pristine_codegen) | GitHub `subdir:` | OpenAPI provider compiler, Provider IR modeling, and Elixir SDK rendering |
| **`pristine_provider_testkit`** | [`apps/pristine_provider_testkit`](https://github.com/nshkrdotcom/pristine/tree/main/apps/pristine_provider_testkit) | GitHub `subdir:` (`:test`) | Shared test harness for downstream SDK conformance and artifact freshness |

## Quick Start

Execute API requests with built-in resilience, authentication, and telemetry:

```elixir
# 1. Build a Foundation-backed production context
context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    auth: [{Pristine.Adapters.Auth.Bearer, token: "secret-token"}]
  )

# 2. Define an operation request specification
request = %{
  id: "widgets.get",
  method: :get,
  path_template: "/v1/widgets/{id}",
  path_params: %{"id" => "wdg_123"},
  auth: %{use_client_default?: true, security_schemes: ["bearerAuth"]},
  retry: "widgets.read",
  circuit_breaker: "widgets_api"
}

# 3. Execute through the resilience pipeline
{:ok, response} = Pristine.execute_request(request, context)
```

## Dependency Configuration

### Production Runtime Adoption

Applications and SDKs consuming the HTTP runtime depend on `:pristine` via Hex:

```elixir
def deps do
  [
    {:pristine, "~> 0.4.0"}
  ]
end
```

### SDK Generation & Verification

Downstream provider SDKs (such as `github_ex` or `notion_sdk`) consume the compiler and verification testkit directly from GitHub:

```elixir
def deps do
  [
    {:pristine, "~> 0.4.0"},
    {:pristine_codegen,
     github: "nshkrdotcom/pristine",
     branch: "main",
     subdir: "apps/pristine_codegen",
     runtime: false},
    {:pristine_provider_testkit,
     github: "nshkrdotcom/pristine",
     branch: "main",
     subdir: "apps/pristine_provider_testkit",
     only: :test}
  ]
end
```

### Local Sibling Development

When working across sibling checkouts on your local machine, configure path dependencies:

```elixir
def deps do
  [
    {:pristine, path: "../pristine/apps/pristine_runtime"},
    {:pristine_codegen, path: "../pristine/apps/pristine_codegen"},
    {:pristine_provider_testkit,
     path: "../pristine/apps/pristine_provider_testkit",
     only: :test}
  ]
end
```

## Package Overview

### [`apps/pristine_runtime`](apps/pristine_runtime/README.md) — Runtime Engine

The published `:pristine` package. It manages:
- **Request Pipeline**: Execution lifecycle, middleware orchestration, and normalized error mapping.
- **Ports & Adapters**: Pluggable transports (Finch, Execution Plane), serializers (JSON), and auth strategies (Bearer, ApiKey, Basic, OAuth2).
- **Resilience**: Exponential backoff, jitter, retry budgets, circuit breakers, and rate limiters backed by `Foundation`.
- **Streaming**: Native Server-Sent Events (SSE) handling and lazy response stream consumption.
- **Client Boundaries**: High-level `Pristine.Client` / `Pristine.Operation` APIs alongside the SDK-facing `Pristine.foundation_context/1` and `Pristine.execute_request/3`.

### [`apps/pristine_codegen`](apps/pristine_codegen/README.md) — SDK Compiler

The build-time compiler for provider SDKs. It provides:
- **OpenAPI Translation**: Converts OpenAPI specifications into typed `PristineCodegen.ProviderIR` data structures.
- **Code Generation**: Generates clean, idiomatic Elixir client modules, schema definitions, and operation helpers.
- **Mix Tasks**: Includes [`mix pristine.codegen.generate`](guides/code-generation-and-artifacts.md), [`mix pristine.codegen.verify`](guides/code-generation-and-artifacts.md), [`mix pristine.codegen.refresh`](guides/code-generation-and-artifacts.md), and [`mix pristine.codegen.ir`](guides/code-generation-and-artifacts.md).

### [`apps/pristine_provider_testkit`](apps/pristine_provider_testkit/README.md) — Provider Testkit

Test infrastructure for downstream provider SDK repositories:
- **Artifact Freshness**: Verifies that committed generated code remains strictly in sync with source specifications.
- **Conformance Testing**: Reusable validation assertions via `PristineProviderTestkit.Conformance.verify_provider/2`.

## Runtime Status: Cancellation & Capability Discovery

The runtime codebase includes a provider-neutral cancellation and transport capability discovery contract (`Pristine.Cancellation`, transport capability callbacks, and `Pristine.RuntimeCapabilities.transport/1`).

Built-in Finch unary transport supports physical HTTP/1.1 cancellation through Execution Plane HTTP 0.2.0 and OTP `:httpc`, including cleanup on caller death. A completed response may win a cancellation race; remote side effects cannot be rolled back.

## Documentation

### Package References
- [Runtime Package README](apps/pristine_runtime/README.md)
- [Codegen Package README](apps/pristine_codegen/README.md)
- [Provider Testkit README](apps/pristine_provider_testkit/README.md)

### User Guides
- [Getting Started](guides/getting-started.md) — Prerequisites, installation, and environment setup
- [Workspace Overview](guides/workspace-overview.md) — Monorepo design and package consumption models
- [Runtime & SDK Usage](guides/runtime-and-sdk-usage.md) — Contexts, operations, auth, and request execution
- [Code Generation & Artifacts](guides/code-generation-and-artifacts.md) — Compiling OpenAPI schemas into Elixir SDKs
- [Provider Verification](guides/provider-verification.md) — Conformance testing for downstream SDKs
- [Testing & Verification](guides/testing-and-verification.md) — Quality verification strategies across layers

### Developer Guides
- [Architecture & Package Boundaries](guides/architecture-and-package-boundaries.md) — System boundaries and hexagonal design principles
- [Runtime Internals](guides/runtime-internals.md) — Execution pipeline, adapters, and lifecycle internals
- [Codegen Internals](guides/codegen-internals.md) — Compiler stages, Provider IR, and renderer architecture
- [Maintaining the Monorepo](guides/maintaining-the-monorepo.md) — Quality gates, versioning, and monorepo workflows

## Workspace Commands

Run these commands from the monorepo root:

### Quality & Acceptance Gates
```bash
mix ci                 # Full monorepo acceptance gate (format, compile, test, credo, dialyzer, docs)
mix quality            # Strict Credo linting and Dialyzer type analysis
```

### Testing
```bash
mix test               # Root workspace contract tests
mix monorepo.test      # Run test suites across all child packages (or: mix mr.test)
```

### Development Lifecycle
```bash
mix monorepo.deps.get  # Fetch dependencies across all packages (or: mix mr.deps.get)
mix monorepo.compile   # Compile all packages with warnings-as-errors (or: mix mr.compile)
mix monorepo.format    # Format code across all packages (or: mix mr.format)
mix monorepo.credo     # Run Credo across all packages (or: mix mr.credo)
mix monorepo.dialyzer  # Run Dialyzer across the workspace (or: mix mr.dialyzer)
mix monorepo.docs      # Build workspace ExDoc documentation (or: mix docs.all)
```

Direct Blitz runner commands can also be invoked via `mix blitz.workspace.impact <task>`.

## License

This repository is released under the [MIT License](LICENSE.md). The root workspace retains the canonical copy in [`LICENSE.md`](LICENSE.md), with a matching copy included in [`apps/pristine_runtime/LICENSE.md`](apps/pristine_runtime/LICENSE.md) for packaged Hex distribution.
