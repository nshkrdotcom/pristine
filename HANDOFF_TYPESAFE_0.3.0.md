# Pristine 0.3.0 local handoff for TypeSafeSDK

Date: 2026-09-16. Runtime and workspace version: **0.3.0**.
Starting commit: `dc54297fa04c17bc381fe068dc13158a57af9ad8`.
The owner committed and pushed the runtime changes as `92c1dd4`.
No package publication was performed during preparation.

## Changes

- Added `Pristine.SDK.ProviderProfile.status_retry_ranges`, defaulting to `[]`.
- Entries are maps with an ascending unit-step integer `:range` within `100..599`
  and the same normalized override keys as exact status overrides.
- Exact status overrides take precedence. Overlapping ranges fail construction.
- The existing classifier consumes resolved overrides; no global 5xx retry rule
  or TypeSafe-specific classifier branch was introduced.
- Added optional Foundation-adapter `retry_budget_ms`: includes the first attempt,
  stops before an over-budget delay, and preserves the last result.
- Zero initial backoff or cap disables backoff while preserving Retry-After.
- Updated runtime dependency constraints, documentation, and dated changelogs.
  Codegen and testkit package versions were not mechanically bumped.

## Verification

Elixir 1.19.5 / OTP 28.3.1, using the existing source-selection hook and the
machine-local bootstrap at
`~/.config/mix_workspace_ops/typesafe_local_bootstrap.exs`.
No MWO registry workflow is required. Execution Plane core resolves from Hex at
0.3.0, matching the committed `~> 0.3.0` requirement; its HTTP package uses the
existing sibling checkout.

From `apps/pristine_runtime`, all passed:

- Dependency resolution and formatting check.
- Compilation with warnings as errors.
- **315 runtime tests**, including range/classifier, budget, and zero-backoff tests.
- Strict Credo and Dialyzer (zero warnings).
- Documentation with warnings as errors.
- `mix hex.build --unpack`, with reviewed runtime package contents and Hex metadata.

The downstream TypeSafeSDK also passed its offline pipeline tests, both live API
operations, static analysis, generated-file verification, docs, and package build.
Testing was limited to runtime and downstream gates relevant to this change; no
unrelated workspace-wide test campaign was run.

Local commands use `~/.local/bin/typesafe-mix` in place of `mix`. The wrapper uses
relative path dependencies for local work and committed Hex requirements for
`hex.build` / `hex.publish`.

## Publication note

The unpacked runtime package is `apps/pristine_runtime/pristine-0.3.0/`.
Before publication, replace the owner's initial HTTP 0.1.0 upload with the
updated package requiring Execution Plane 0.3.0. The previous HTTP lock entry
was removed so `mix deps.get` fetches the replacement metadata and checksum.
All direct requirements and resolved dependencies are refreshed. Latest Cowlib
2.20.0 still has two Hex advisories in the development/test graph; see the
publication handoff. Final source and release-note changes are committed and pushed.

The minimal release order is HTTP 0.1.0 → Pristine runtime 0.3.0 → TypeSafeSDK
0.1.0. Pristine Codegen and Testkit do not need publishing. Follow
`../typesafe_sdk/PUBLISHING.md` for the complete commands and Hex version checks.
