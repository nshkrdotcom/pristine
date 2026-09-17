# Changelog

All notable changes to the published `pristine` runtime package are documented
in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added opaque `Pristine.Cancellation` tokens and a standardized
  `%Pristine.Error{type: :cancelled}` terminal error.
- Added optional `Pristine.Ports.Transport.capabilities/1` and
  `send_cancelable/3` callbacks while keeping `send/2` backward compatible.
- Added provider-neutral `Pristine.RuntimeCapabilities.transport/1` fail-closed
  capability discovery.
- Added cancellation-aware Foundation retry waits and regression tests for token,
  classifier, capability, retry-delay, and pipeline preflight behavior.

### Changed

- Default HTTP result classification treats cancellation as non-retryable with
  breaker outcome `:ignore`, no limiter backoff, and `:cancelled` telemetry.
- Cancelable execution never falls back to ordinary transport `send/2`.
- Built-in Finch explicitly advertises unary cancellation and cleanup as
  unsupported until physical Execution Plane cancellation is implemented and
  proven by the required real-HTTP acceptance test.

### Verification Status

- This work intentionally remains unreleased on the 0.3.1 version line until
  physical Finch cancellation is implemented through the Execution Plane and the
  required real-HTTP acceptance/QC gates pass. See `HANDOFF.md` for the remaining
  integration and verification work.

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

- Added `Pristine.GovernedAuthority` and governed credential auth handling so
  authority-selected HTTP credentials can execute while direct base URLs,
  headers, auth overrides, and OAuth saved-token sources fail closed in
  governed mode.
- Updated the runtime package source constraint to consume `sinter` `0.3.2`.
- Unary HTTP execution now uses the separately published `execution_plane` and
  `execution_plane_http` packages.

## [0.2.1] - 2026-04-01

### Changed

- Expanded the runtime package docs to clarify auth and token-source behavior
  for Foundation-backed clients.

### Fixed

- Synchronized the package changelog with the `0.2.1` runtime release metadata.

## [0.2.0] - 2026-03-27

### Added

- Added the client and operation-centered runtime surface around
  `Pristine.Client`, `Pristine.Operation`, `Pristine.Response`, and the
  SDK-facing `Pristine.SDK.OpenAPI.Client` helpers.
- Added package-local guides, examples, docs assets, and HexDocs structure for
  the published runtime package.
- Added `Pristine.SDK.ProviderProfile` and the request-spec execution boundary
  used by generated provider SDKs.

### Changed

- Rebuilt the runtime around explicit request, endpoint metadata, and adapter
  contracts while keeping Foundation-backed execution as the recommended
  production profile.
- Moved the runtime into `apps/pristine_runtime` as the published package
  boundary inside the monorepo.

### Fixed

- Improved HTTP result classification and retry behavior.
- Handled OAuth error payloads returned inside HTTP 2xx responses.

## [0.1.0] - 2026-03-14

### Initial Release