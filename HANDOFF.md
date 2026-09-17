# Pristine 0.4.0 / Execution Plane HTTP 0.2.0 release handoff

Prepared on 2026-09-17 with Erlang 28.3.1 and Elixir 1.19.5-otp-28.

## Release order

1. Publish `execution_plane_http 0.2.0` from
   `../execution_plane/protocols/execution_plane_http`.
2. Resolve the now-published dependency with `mix deps.get` in
   `apps/pristine_runtime`, then publish `pristine 0.4.0` there.

Future tags are `execution_plane_http-v0.2.0` and `pristine-v0.4.0` in their
respective repositories. No tags or packages were published during preparation.
The tooling packages retain their versions.

Pristine's committed dependency is `execution_plane_http ~> 0.2.0`. Until HTTP
0.2.0 is published, source QC uses the existing machine-local MWO bootstrap at
`~/.config/mix_workspace_ops/typesafe_local_bootstrap.exs`; the Hex artifact has
ordinary Hex dependencies and no local source coordinates. The obsolete HTTP
0.1.0 lock entry was removed; no checksum for an unpublished package was invented.
The only new locked packages are Supertester and its StreamData dependency.

## Consumer contract

Create `Pristine.Cancellation.new/0`, pass it as `cancellation:` to
`Pristine.execute_request/3`, and cancel it from another process with
`Pristine.Cancellation.cancel/1`. Cancellation returns a non-retryable
`%Pristine.Error{type: :cancelled}`. Default Foundation retry waits wake on
cancellation and no later attempt starts. A custom sleeper must cooperate with
the token to interrupt its own blocking work.

`Pristine.RuntimeCapabilities.transport/1` reports unary cancellation and cleanup
as supported for the built-in Finch compatibility adapter. Other adapters fail
closed unless they declare both capabilities and implement `send_cancelable/3`.

The real unary transport is Execution Plane HTTP -> OTP `:httpc`. The pipeline
acceptance test proves real HTTP/1.1 socket closure, late-write failure, normal
completion winning, and caller-death cleanup. Lower tests additionally prove
worker termination and wait-timeout mailbox/monitor cleanup. Watchers unregister
before normal return; token notifications use process aliases to drop late wakes.
HTTP/2 unary support is not claimed. Cancellation cannot undo remote side effects
or guarantee that the upstream never received the request.

The existing `Context.result_classifier` extension remains the only generic
classification hook. Cancellation does not introduce a second retry engine.
TypeSafeSDK was not modified.

## Verification

Execution Plane's package/root `mix ci`, focused cancellation and active gateway
regressions, `mix hex.build --unpack`, and `mix hex.publish --dry-run --yes` passed.
Its unpacked artifact also compiled against the published Hex core 0.3.0 without
local source substitution. See the HTTP package's `RELEASE_READINESS.md`.

Pristine QC passed:

- Runtime `mix test`, `mix test --seed 0`, and `mix test --seed 12345`: 347 tests,
  zero failures on each run, including the full-pipeline physical cancellation
  acceptance, retry/classifier regressions, and existing streaming tests.
- Runtime strict Credo and `mix dialyzer --force-check`: zero findings.
- Root `mix ci`: dependency bootstrap, formatter, warnings-as-errors compilation,
  workspace tests, strict Credo, workspace Dialyzer, and docs.
- Runtime `mix hex.build --unpack`: 0.4.0 artifact with Hex HTTP ~> 0.2.0.

Root CI now bootstraps all isolated dependency trees before impact gates.
After HTTP publication, the final Hex-only dependency resolution is part of the
release sequence; it cannot resolve an unpublished HTTP 0.2.0 from Hex today.

## Hex dependency validation — 2026-09-17

Execution Plane HTTP 0.2.0 is now published, with tag
`execution_plane_http-v0.2.0` pushed. The runtime resolved it from Hex and the
real checksum is committed in `mix.lock`. Against that published dependency,
runtime formatting, warnings-as-errors compilation, 347 tests, strict Credo,
Dialyzer (zero errors/skips), warnings-as-errors docs and the full Hex publish
dry run all passed. No runtime source changes were required.
