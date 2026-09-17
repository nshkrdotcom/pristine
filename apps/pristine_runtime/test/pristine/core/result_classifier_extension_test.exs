defmodule Pristine.Core.ResultClassifierExtensionTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Pristine.Adapters.{CircuitBreaker, RateLimit, Retry, Serializer}
  alias Pristine.Core.{Context, Request, Response}
  alias Pristine.Error

  defmodule Transport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def send(%Request{}, %Context{transport_opts: opts}) do
      attempt_key = Keyword.fetch!(opts, :attempt_key)
      attempt = Process.get(attempt_key, 0)
      Process.put(attempt_key, attempt + 1)
      Kernel.send(Keyword.fetch!(opts, :test_pid), {:transport_attempt, attempt})

      case Keyword.fetch!(opts, :mode) do
        :custom_failure_then_success when attempt == 0 ->
          {:error, :provider_specific_transient_failure}

        :http_503 ->
          {:ok, %Response{status: 503, headers: %{}, body: "{}"}}

        _other ->
          {:ok, %Response{status: 200, headers: %{}, body: "{}"}}
      end
    end
  end

  defmodule Classifier do
    @behaviour Pristine.Ports.ResultClassifier

    alias Pristine.Adapters.ResultClassifier.HTTP
    alias Pristine.Core.Response

    @impl true
    def classify(
          {:error, :provider_specific_transient_failure},
          endpoint,
          context,
          opts
        ) do
      notify(context, endpoint, opts, :custom_failure)

      %{
        retry?: true,
        breaker_outcome: :ignore,
        telemetry: %{classification: :provider_specific_transient_failure}
      }
    end

    def classify({:ok, %Response{status: 503}}, endpoint, context, opts) do
      notify(context, endpoint, opts, :suppressed_503)

      %{
        retry?: false,
        breaker_outcome: :ignore,
        telemetry: %{classification: :provider_specific_non_retryable}
      }
    end

    def classify(result, endpoint, context, opts) do
      HTTP.classify(result, endpoint, context, opts)
    end

    defp notify(context, endpoint, opts, kind) do
      send(
        context.telemetry_metadata.test_pid,
        {:classifier_seen, kind, endpoint.id, context.transport,
         Keyword.get(opts, :classifier_marker)}
      )
    end
  end

  @request %{id: "classifier-test", method: :get, path: "/v1/classifier-test"}

  test "custom classifier can make a custom transport failure retryable" do
    context = context(:custom_failure_then_success)

    assert {:ok, _response} =
             Pristine.execute_request(@request, context,
               classifier_marker: :visible_to_classifier
             )

    assert_received {:transport_attempt, 0}
    assert_received {:transport_attempt, 1}

    assert_received {:classifier_seen, :custom_failure, "classifier-test", Transport,
                     :visible_to_classifier}
  end

  test "custom classifier can suppress retry of an otherwise retryable HTTP result" do
    context = context(:http_503)

    assert {:error, %Error{status: 503}} =
             Pristine.execute_request(@request, context, classifier_marker: :suppress_retry)

    assert_received {:transport_attempt, 0}
    refute_received {:transport_attempt, 1}

    assert_received {:classifier_seen, :suppressed_503, "classifier-test", Transport,
                     :suppress_retry}
  end

  defp context(mode) do
    attempt_key = make_ref()

    Context.new(
      base_url: "https://example.test",
      serializer: Serializer.JSON,
      transport: Transport,
      transport_opts: [test_pid: self(), attempt_key: attempt_key, mode: mode],
      retry: Retry.Foundation,
      retry_opts: [
        max_attempts: 2,
        base_ms: 0,
        max_ms: 0,
        sleep_fun: fn _delay_ms -> :ok end
      ],
      result_classifier: Classifier,
      rate_limiter: RateLimit.Noop,
      circuit_breaker: CircuitBreaker.Noop,
      telemetry_metadata: %{test_pid: self()}
    )
  end
end
