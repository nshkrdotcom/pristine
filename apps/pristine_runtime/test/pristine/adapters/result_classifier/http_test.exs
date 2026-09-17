defmodule Pristine.Adapters.ResultClassifier.HTTPTest do
  use ExUnit.Case, async: true

  alias ExecutionPlane.Contracts.Failure
  alias Pristine.Adapters.ResultClassifier.HTTP
  alias Pristine.Core.{Context, EndpointMetadata, Response}
  alias Pristine.SDK.ProviderProfile

  test "range classification is provider-owned and can disable built-in retries" do
    profile =
      ProviderProfile.new!(
        provider: :demo,
        status_retry_ranges: [
          %{
            range: 500..599,
            retry?: true,
            telemetry_classification: :upstream_failure,
            breaker_outcome: :failure
          }
        ]
      )

    for status <- [501, 505, 520, 599] do
      result =
        HTTP.classify(
          {:ok, %Response{status: status}},
          endpoint(:get),
          %Context{provider_profile: profile},
          []
        )

      assert result.retry?
      assert result.breaker_outcome == :failure
      assert result.telemetry.classification == :upstream_failure

      baseline =
        HTTP.classify(
          {:ok, %Response{status: status}},
          endpoint(:get),
          %Context{},
          []
        )

      refute baseline.retry?
      assert baseline.breaker_outcome == :ignore
    end

    disabled =
      ProviderProfile.new!(
        provider: :demo,
        status_retry_ranges: [%{range: 500..599, retry?: false}]
      )

    refute HTTP.classify(
             {:ok, %Response{status: 503}},
             endpoint(:get),
             %Context{provider_profile: disabled},
             []
           ).retry?
  end

  describe "classify/4" do
    test "ignores caller-side 4xx responses for circuit breaker health" do
      classification =
        HTTP.classify(
          {:ok, %Response{status: 404}},
          endpoint(:get),
          %Context{},
          []
        )

      assert classification.retry? == false
      assert classification.breaker_outcome == :ignore
      assert classification.telemetry.classification == :client_error
    end

    test "retries upstream failures for safe methods" do
      classification =
        HTTP.classify(
          {:ok, %Response{status: 503}},
          endpoint(:get),
          %Context{},
          []
        )

      assert classification.retry? == true
      assert classification.breaker_outcome == :failure
      assert classification.telemetry.classification == :upstream_failure
    end

    test "does not retry upstream failures for non-idempotent requests" do
      classification =
        HTTP.classify(
          {:ok, %Response{status: 503}},
          endpoint(:post),
          %Context{},
          []
        )

      assert classification.retry? == false
      assert classification.breaker_outcome == :failure
    end

    test "retries upstream failures for explicitly idempotent requests" do
      classification =
        HTTP.classify(
          {:ok, %Response{status: 503}},
          endpoint(:post, idempotency: true),
          %Context{},
          []
        )

      assert classification.retry? == true
      assert classification.breaker_outcome == :failure
    end

    test "preserves rate-limit backoff behavior" do
      classification =
        HTTP.classify(
          {:ok, %Response{status: 429, headers: %{"retry-after" => "7"}}},
          endpoint(:post),
          %Context{},
          []
        )

      assert classification.retry? == true
      assert classification.retry_after_ms == 7_000
      assert classification.limiter_backoff_ms == 7_000
      assert classification.breaker_outcome == :ignore
      assert classification.telemetry.classification == :rate_limited
    end

    test "treats execution-plane transport failures as retryable transport errors" do
      classification =
        HTTP.classify(
          {:error,
           {:execution_plane_transport,
            Failure.new!(%{failure_class: :transport_failed, reason: "http request failed"}), %{}}},
          endpoint(:get),
          %Context{},
          []
        )

      assert classification.retry? == true
      assert classification.breaker_outcome == :failure
      assert classification.telemetry.classification == :transport_error
    end
  end

  defp endpoint(method, attrs \\ []) do
    struct!(EndpointMetadata, Keyword.merge([id: "ping", method: method, path: "/ping"], attrs))
  end
end
