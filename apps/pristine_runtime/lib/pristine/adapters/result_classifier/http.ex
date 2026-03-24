defmodule Pristine.Adapters.ResultClassifier.HTTP do
  @moduledoc """
  Generic HTTP result classifier for Pristine request execution.
  """

  @behaviour Pristine.Ports.ResultClassifier

  alias Pristine.Core.{Response, ResultClassification}
  alias Pristine.Response, as: PublicResponse
  alias Pristine.SDK.ProviderProfile

  @failure_statuses [408, 500, 502, 503, 504]

  @impl true
  def classify({:ok, %Response{} = response}, endpoint, context, _opts) do
    response
    |> response_classification(endpoint, context)
    |> ResultClassification.normalize()
  end

  def classify({:ok, %PublicResponse{} = response}, endpoint, context, opts) do
    classify(
      {:ok,
       %Response{
         status: response.status,
         headers: response.headers,
         body: response.body,
         metadata: response.metadata
       }},
      endpoint,
      context,
      opts
    )
  end

  def classify({:error, :circuit_open}, endpoint, context, _opts) do
    retry_group = ProviderProfile.retry_group(provider_profile(context), endpoint)

    ResultClassification.normalize(%{
      retry?: false,
      breaker_outcome: :ignore,
      telemetry: telemetry(endpoint, retry_group, :circuit_open, false, :ignore)
    })
  end

  def classify({:error, reason}, endpoint, context, _opts) do
    profile = provider_profile(context)
    retry_group = ProviderProfile.retry_group(profile, endpoint)

    retryable =
      retryable_transport_error?(reason) and
        ProviderProfile.transport_retryable?(profile, endpoint)

    ResultClassification.normalize(%{
      retry?: retryable,
      breaker_outcome: :failure,
      telemetry: telemetry(endpoint, retry_group, :transport_error, retryable, :failure)
    })
  end

  def classify(_result, _endpoint, _context, _opts), do: ResultClassification.normalize(nil)

  defp response_classification(%Response{status: status, headers: headers}, endpoint, context) do
    profile = provider_profile(context)
    retry_after_ms = ProviderProfile.retry_after_ms(profile, headers)
    retry_group = ProviderProfile.retry_group(profile, endpoint)
    rate_limited? = ProviderProfile.rate_limited?(profile, status, headers, endpoint)
    status_override = ProviderProfile.status_retry_override(profile, status)

    override_applies? =
      is_map(status_override) and
        ProviderProfile.override_applies?(status_override, profile, endpoint)

    case response_classification_kind(rate_limited?, override_applies?, status) do
      :rate_limited ->
        rate_limited_result(profile, endpoint, retry_group, retry_after_ms)

      :override ->
        override_result(status_override, profile, endpoint, retry_group, retry_after_ms)

      :upstream_failure ->
        upstream_failure_result(profile, endpoint, retry_group, retry_after_ms)

      :client_error ->
        result(endpoint, retry_group, :client_error, false, :ignore)

      :success ->
        result(endpoint, retry_group, :success, false, :success)

      :ignored ->
        result(endpoint, retry_group, :ignored, false, :ignore)
    end
  end

  defp response_classification_kind(true, _override_applies?, _status), do: :rate_limited
  defp response_classification_kind(false, true, _status), do: :override

  defp response_classification_kind(false, false, status) when status in @failure_statuses,
    do: :upstream_failure

  defp response_classification_kind(false, false, status) when status >= 400 and status < 500,
    do: :client_error

  defp response_classification_kind(false, false, status) when status >= 200 and status < 400,
    do: :success

  defp response_classification_kind(false, false, _status), do: :ignored

  defp rate_limited_result(profile, endpoint, retry_group, retry_after_ms) do
    retryable = ProviderProfile.rate_limit_retryable?(profile, endpoint)

    result(endpoint, retry_group, :rate_limited, retryable, :ignore,
      retry_after_ms: retry_after_ms,
      limiter_backoff_ms: retry_after_ms
    )
  end

  defp override_result(status_override, profile, endpoint, retry_group, retry_after_ms) do
    retryable = ProviderProfile.override_retry?(status_override, profile, endpoint)
    breaker_outcome = Map.get(status_override, :breaker_outcome, :ignore)

    telemetry_classification =
      Map.get(status_override, :telemetry_classification, :client_error)

    result(endpoint, retry_group, telemetry_classification, retryable, breaker_outcome,
      retry_after_ms: retry_after_ms,
      limiter_backoff_ms: limiter_backoff_ms(status_override, retry_after_ms)
    )
  end

  defp upstream_failure_result(profile, endpoint, retry_group, retry_after_ms) do
    retryable = ProviderProfile.retryable_group?(profile, endpoint)

    result(endpoint, retry_group, :upstream_failure, retryable, :failure,
      retry_after_ms: retry_after_ms
    )
  end

  defp limiter_backoff_ms(status_override, retry_after_ms) do
    case Map.get(status_override, :limiter_backoff_ms) do
      :retry_after -> retry_after_ms
      value when is_integer(value) and value >= 0 -> value
      _other -> nil
    end
  end

  defp result(endpoint, retry_group, classification, retryable, breaker_outcome, opts \\ []) do
    %{
      retry?: retryable,
      retry_after_ms: Keyword.get(opts, :retry_after_ms),
      limiter_backoff_ms: Keyword.get(opts, :limiter_backoff_ms),
      breaker_outcome: breaker_outcome,
      telemetry: telemetry(endpoint, retry_group, classification, retryable, breaker_outcome)
    }
  end

  defp retryable_transport_error?(%Mint.TransportError{}), do: true
  defp retryable_transport_error?(%Mint.HTTPError{}), do: true
  defp retryable_transport_error?(:timeout), do: true
  defp retryable_transport_error?(_reason), do: false

  defp telemetry(endpoint, retry_group, classification, retryable, breaker_outcome) do
    %{
      classification: classification,
      retryable: retryable,
      breaker_outcome: breaker_outcome,
      resource: Map.get(endpoint, :resource) || Map.get(endpoint, "resource"),
      retry_group: retry_group
    }
  end

  defp provider_profile(%{provider_profile: provider_profile}), do: provider_profile
  defp provider_profile(_context), do: nil
end
