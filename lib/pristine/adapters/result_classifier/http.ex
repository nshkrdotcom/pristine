defmodule Pristine.Adapters.ResultClassifier.HTTP do
  @moduledoc """
  Generic HTTP result classifier for Pristine request execution.
  """

  @behaviour Pristine.Ports.ResultClassifier

  alias Foundation.Retry.HTTP, as: RetryHTTP
  alias Pristine.Core.{Response, ResultClassification}

  @failure_statuses [408, 500, 502, 503, 504]

  @impl true
  def classify({:ok, %Response{status: status, headers: headers}}, _endpoint, _context, _opts) do
    retry_after_ms = retry_after_ms(headers)

    classification =
      cond do
        status == 429 ->
          %{
            retry?: true,
            retry_after_ms: retry_after_ms,
            limiter_backoff_ms: retry_after_ms,
            breaker_outcome: :ignore,
            telemetry: %{
              classification: :rate_limited,
              retryable: true,
              breaker_outcome: :ignore
            }
          }

        status in @failure_statuses ->
          %{
            retry?: true,
            retry_after_ms: retry_after_ms,
            limiter_backoff_ms: nil,
            breaker_outcome: :failure,
            telemetry: %{
              classification: :upstream_failure,
              retryable: true,
              breaker_outcome: :failure
            }
          }

        status >= 200 and status < 500 ->
          %{
            retry?: false,
            retry_after_ms: nil,
            limiter_backoff_ms: nil,
            breaker_outcome: :success,
            telemetry: %{
              classification: :success,
              retryable: false,
              breaker_outcome: :success
            }
          }

        true ->
          %{
            retry?: false,
            retry_after_ms: nil,
            limiter_backoff_ms: nil,
            breaker_outcome: :ignore,
            telemetry: %{
              classification: :ignored,
              retryable: false,
              breaker_outcome: :ignore
            }
          }
      end

    ResultClassification.normalize(classification)
  end

  def classify({:error, :circuit_open}, _endpoint, _context, _opts) do
    ResultClassification.normalize(%{
      retry?: false,
      breaker_outcome: :ignore,
      telemetry: %{classification: :circuit_open, retryable: false, breaker_outcome: :ignore}
    })
  end

  def classify({:error, reason}, _endpoint, _context, _opts) do
    ResultClassification.normalize(%{
      retry?: retryable_transport_error?(reason),
      breaker_outcome: :failure,
      telemetry: %{
        classification: :transport_error,
        retryable: retryable_transport_error?(reason),
        breaker_outcome: :failure
      }
    })
  end

  def classify(_result, _endpoint, _context, _opts), do: ResultClassification.normalize(nil)

  defp retry_after_ms(headers) do
    if retry_after_header?(headers) do
      RetryHTTP.parse_retry_after(headers, 0)
    end
  end

  defp retry_after_header?(headers) when is_map(headers) do
    Enum.any?(headers, fn {key, _value} ->
      normalized = String.downcase(to_string(key))
      normalized in ["retry-after", "retry-after-ms"]
    end)
  end

  defp retry_after_header?(headers) when is_list(headers) do
    Enum.any?(headers, fn
      {key, _value} ->
        normalized = String.downcase(to_string(key))
        normalized in ["retry-after", "retry-after-ms"]

      _other ->
        false
    end)
  end

  defp retry_after_header?(_headers), do: false

  defp retryable_transport_error?(%Mint.TransportError{}), do: true
  defp retryable_transport_error?(%Mint.HTTPError{}), do: true
  defp retryable_transport_error?(:timeout), do: true
  defp retryable_transport_error?(_reason), do: false
end
