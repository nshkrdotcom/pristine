# Runtime Internals

The runtime is organized around a small public API and a broader adapter-driven
execution core.

## Core Flow

The public entrypoints eventually converge on `Pristine.Core.Pipeline`:

- `Pristine.execute/3` accepts `Pristine.Client` and `Pristine.Operation`
- `Pristine.execute_request/3` accepts a request-spec map plus
  `Pristine.Core.Context`
- `Pristine.stream/3` drives the streaming transport path

The pipeline is responsible for:

- turning operations or request specs into normalized endpoint metadata
- encoding request payloads with the configured serializer
- building transport requests
- applying retry, rate limiting, circuit breaking, and telemetry
- decoding and classifying responses

## Context And Ports

`Pristine.Core.Context` is the internal dependency carrier. It stores the
runtime adapters and configuration such as:

- transport and stream transport
- serializer and multipart support
- retry, rate limiting, circuit breaker, and admission control
- telemetry emitters and metadata
- auth defaults, retry policies, and type schemas

The `Pristine.Ports.*` modules define the expected contracts, while
`Pristine.Adapters.*` modules provide built-in implementations such as Finch
transport, JSON serialization, OAuth helpers, SSE streaming, and Foundation
resilience adapters.

## Profiles And SDK Support

`Pristine.Profiles.Foundation` builds opinionated production contexts with the
recommended resilience and telemetry defaults.

`Pristine.SDK.OpenAPI.Client` is the SDK-facing helper layer that turns request
maps into runtime-ready request specs or `Pristine.Operation` values. That
keeps generated provider facades thin and stable even when they expose richer
provider-specific method signatures.

## OAuth Control Plane

`Pristine.OAuth2` stays inside the runtime package because token acquisition and
refresh still rely on the same transport and serializer seams as ordinary API
calls. Browser launch, callback capture, and token storage are optional adapter
boundaries layered around that control plane.

## Cancellation And Capability Flow

Unary cancellation remains inside the existing pipeline rather than introducing
a second execution path. `Pristine.Core.Pipeline` performs cancellation
preflight, requires the configured transport to advertise both
`:unary_cancellation` and `:cancellation_cleanup`, and routes cancelable sends
only through the optional `Pristine.Ports.Transport.send_cancelable/3` callback.
A legacy `send/2` transport remains valid for ordinary execution.

`Pristine.Cancellation` is an opaque, terminal token backed by atomic state. A
small duplicate-key registry owned by the Pristine supervision tree wakes retry
waiters without creating a process per token. The Foundation retry adapter uses
the same token in the existing retry loop; cancellation during its normal wait
returns `%Pristine.Error{type: :cancelled}` and prevents the next attempt.

`Pristine.Adapters.ResultClassifier.HTTP` treats cancellation as non-retryable,
with breaker outcome `:ignore`, no limiter/admission backoff, and telemetry
classification `:cancelled`. The existing `Context.result_classifier` module or
function remains the one generic extension point for provider/SDK-specific result
classification; no second retry predicate system is added.

Capability discovery is declarative. Missing, malformed, or absent entries are
`:unverified`; explicit negative entries are `:unsupported`; only positive
advertisements are `:supported`. Third-party declarations are their owners'
contracts, while Pristine-owned adapters only advertise support after acceptance
tests prove it.
