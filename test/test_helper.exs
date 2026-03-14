Mox.defmock(Pristine.TransportMock, for: Pristine.Ports.Transport)
Mox.defmock(Pristine.StreamTransportMock, for: Pristine.Ports.StreamTransport)
Mox.defmock(Pristine.SerializerMock, for: Pristine.Ports.Serializer)
Mox.defmock(Pristine.RetryMock, for: Pristine.Ports.Retry)
Mox.defmock(Pristine.TelemetryMock, for: Pristine.Ports.Telemetry)
Mox.defmock(Pristine.AuthMock, for: Pristine.Ports.Auth)
Mox.defmock(Pristine.MultipartMock, for: Pristine.Ports.Multipart)
Mox.defmock(Pristine.CircuitBreakerMock, for: Pristine.Ports.CircuitBreaker)
Mox.defmock(Pristine.RateLimitMock, for: Pristine.Ports.RateLimit)
Mox.defmock(Pristine.FutureMock, for: Pristine.Ports.Future)

Code.require_file("support/openapi_named_typed_map_fixture.exs", __DIR__)

if function_exported?(Logger, :put_module_level, 2) and Code.ensure_loaded?(Bandit.Clock) do
  Logger.put_module_level(Bandit.Clock, :error)
end

ExUnit.start(capture_log: true)
