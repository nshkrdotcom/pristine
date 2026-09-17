defmodule Pristine.Adapters.ResultClassifier.HTTPCancellationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Pristine.Adapters.ResultClassifier.HTTP
  alias Pristine.Core.Context
  alias Pristine.Error

  @endpoint %{id: "cancel-test", resource: :test, retry: nil}

  test "default cancellation classification is terminal and ignored by resilience state" do
    classification =
      HTTP.classify({:error, Error.cancelled_error()}, @endpoint, Context.new(), [])

    refute classification.retry?
    assert classification.breaker_outcome == :ignore
    assert classification.limiter_backoff_ms == nil
    assert classification.retry_after_ms == nil
    assert classification.telemetry.classification == :cancelled
    assert classification.telemetry.retryable == false
    assert classification.telemetry.breaker_outcome == :ignore
  end

  test "unsupported cancellation capability is not an upstream failure" do
    classification =
      HTTP.classify(
        {:error,
         {:unsupported_transport_capabilities, LegacyTransport,
          %{unary_cancellation: :unverified}}},
        @endpoint,
        Context.new(),
        []
      )

    refute classification.retry?
    assert classification.breaker_outcome == :ignore
    assert classification.telemetry.classification == :unsupported_transport_capability
  end
end
