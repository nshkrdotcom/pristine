# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Replaced dynamic atom conversion and pattern-engine parsing in runtime and
  codegen boundaries with bounded identifiers and deterministic scanners.
- Updated source package constraints to consume `sinter` `0.3.1`.

## [0.2.1] - 2026-04-01

### Changed

- Aligned the root workspace docs and dependency examples with the `0.2.1`
  runtime release.
- Documented the direct `mix mr.*` aliases and the underlying
  `mix blitz.workspace <task>` runner more clearly in the workspace README.

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
