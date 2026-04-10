defmodule Pristine.Adapters.ResultClassifier.HTTPTest do
  use ExUnit.Case, async: true

  alias ExecutionPlane.Contracts.Failure
  alias Pristine.Adapters.ResultClassifier.HTTP
  alias Pristine.Core.{EndpointMetadata, Response}

  describe "classify/4" do
    test "ignores caller-side 4xx responses for circuit breaker health" do
      classification =
        HTTP.classify(
          {:ok, %Response{status: 404}},
          endpoint(:get),
          %Pristine.Core.Context{},
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
          %Pristine.Core.Context{},
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
          %Pristine.Core.Context{},
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
          %Pristine.Core.Context{},
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
          %Pristine.Core.Context{},
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
          %Pristine.Core.Context{},
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
