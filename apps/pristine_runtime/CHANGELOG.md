# Changelog

All notable changes to the published `pristine` runtime package are documented
in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
