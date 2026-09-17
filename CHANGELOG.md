# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-09-17

### Added

- Added opaque `Pristine.Cancellation` tokens and a standardized
  `%Pristine.Error{type: :cancelled}` terminal error.
- Added optional `c:Pristine.Ports.Transport.capabilities/1` and
  `send_cancelable/3` callbacks while keeping `send/2` backward compatible.
- Added provider-neutral `Pristine.RuntimeCapabilities.transport/1` fail-closed
  capability discovery.
- Added cancellation-aware Foundation retry waits and regression tests for token,
  classifier, capability, retry-delay, and pipeline preflight behavior.

### Changed

- Default HTTP result classification treats cancellation as non-retryable with
  breaker outcome `:ignore`, no limiter backoff, and `:cancelled` telemetry.
- Cancelable execution never falls back to ordinary transport `send/2`.
- Built-in Finch supports physical unary cancellation and cleanup through
  Execution Plane HTTP 0.2.0 and OTP `:httpc`, with real HTTP/1.1 socket coverage
  for cancellation, normal completion, and caller death.
- Cancellation waits for lower execution termination and removes its watcher.

## [0.3.1] - 2026-09-17

### Fixed

- Require Foundation 0.2.2 for supervised default ETS registries and caller-owned
  explicit registries, eliminating transfers to Erlang `:init` after worker exit.
- Honor live explicit rate-limit registries without requiring an ETS heir;
  delegate default-registry ownership/recovery to Foundation instead of creating
  per-request replacement tables or overwriting Foundation's persistent cache.
- Include runtime guides in the Hex package used to build documentation.

## [0.3.0] - 2026-09-16

- Refresh all runtime, optional, and development dependency requirements and the
  resolved lockfile, including Execution Plane 0.3.0, Bandit 1.12.5, and Mint 1.10.0.

### Added

- Optional `retry_budget_ms` in the Foundation adapter stops before an over-budget delay and preserves the last result.
- Zero initial backoff or cap disables backoff while preserving Retry-After.
- Provider-defined HTTP status range overrides through `status_retry_ranges`.
- Exact status overrides take precedence over ranges; overlapping ranges are rejected.
- Existing provider behavior is unchanged when no ranges are configured.

### Changed

- Added governed Pristine HTTP authority docs and runtime fail-closed behavior
  for direct base URLs, headers, auth overrides, and OAuth saved-token sources
  while preserving standalone direct auth compatibility.
- Replaced dynamic atom conversion and pattern-engine parsing in runtime and
  codegen boundaries with bounded identifiers and deterministic scanners.
- Updated source package constraints to consume `sinter` `0.3.2`.
- Unary HTTP execution now uses the separately published `execution_plane` and
  `execution_plane_http` packages.

## [0.2.1] - 2026-04-01

### Changed

- Aligned the root workspace docs and dependency examples with the `0.2.1`
  runtime release.
- Documented the direct `mix mr.*` aliases and the underlying
  `mix blitz.workspace.impact <task>` runner more clearly in the workspace README.

### Fixed

- Synchronized workspace release metadata and changelog history after the
  `0.2.0` monorepo split release.

## [0.2.0] - 2026-03-27

### Added

- Split the workspace into publishable `pristine_runtime` and
  `pristine_codegen` child apps plus the `pristine_provider_testkit` helper
  app, each with its own package docs and tests.
- Added the shared code generation compiler pipeline, canonical
  `PristineCodegen.ProviderIR`, artifact rendering and verification support, and
  the generator, verifier, IR inspection, and refresh workspace tasks for the
  codegen toolchain.
- Added runtime-facing `Pristine.Client`, `Pristine.Operation`,
  `Pristine.Response`, `Pristine.SDK.OpenAPI.Client`, and
  `Pristine.SDK.ProviderProfile` modules to support both direct runtime use and
  generated provider SDKs.
- Added Blitz workspace orchestration and root contract tests for packaging,
  docs, and monorepo task policy.

### Changed

- Reworked the repo root into a tooling and docs workspace instead of a single
  runtime package, with downstream consumers expected to depend on child apps
  via sibling `path:` deps or GitHub `subdir:` fallbacks.
- Rebuilt the runtime around explicit client, operation, request-spec, and
  adapter contracts while keeping Foundation-backed execution, OAuth, and
  streaming support inside the runtime package.
- Hardened dependency boundaries and verification against Elixir 1.19 across
  the workspace and package apps.
- Restructured HexDocs into a guide portal at the root and package-specific
  guides inside the child apps.

### Fixed

- Improved HTTP result classification and retry behavior in the runtime.
- Handled OAuth error payloads returned inside HTTP 2xx responses.

## [0.1.0] - 2026-03-14

### Initial Release

[0.4.0]: https://github.com/nshkrdotcom/pristine/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/nshkrdotcom/pristine/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/nshkrdotcom/pristine/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/nshkrdotcom/pristine/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/nshkrdotcom/pristine/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nshkrdotcom/pristine/releases/tag/v0.1.0
