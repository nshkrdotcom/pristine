defmodule Pristine.Core.ResultClassification do
  @moduledoc """
  Normalized classification for a single request outcome.

  Pristine uses this structure to coordinate retry, shared rate-limit learning,
  circuit-breaker accounting, and telemetry annotations from one classified
  outcome contract.
  """

  @type breaker_outcome :: :success | :failure | :ignore

  @type t :: %__MODULE__{
          retry?: boolean(),
          retry_after_ms: non_neg_integer() | nil,
          limiter_backoff_ms: non_neg_integer() | nil,
          breaker_outcome: breaker_outcome(),
          telemetry: map()
        }

  defstruct retry?: false,
            retry_after_ms: nil,
            limiter_backoff_ms: nil,
            breaker_outcome: :ignore,
            telemetry: %{}

  @spec normalize(t() | map() | keyword() | nil) :: t()
  def normalize(%__MODULE__{} = classification), do: classification

  def normalize(classification) when is_list(classification) do
    classification
    |> Enum.into(%{})
    |> normalize()
  end

  def normalize(classification) when is_map(classification) do
    %__MODULE__{
      retry?: Map.get(classification, :retry?, false),
      retry_after_ms: normalize_ms(Map.get(classification, :retry_after_ms)),
      limiter_backoff_ms: normalize_ms(Map.get(classification, :limiter_backoff_ms)),
      breaker_outcome: normalize_breaker_outcome(Map.get(classification, :breaker_outcome)),
      telemetry: normalize_telemetry(Map.get(classification, :telemetry, %{}))
    }
  end

  def normalize(_classification), do: %__MODULE__{}

  defp normalize_ms(value) when is_integer(value) and value >= 0, do: value
  defp normalize_ms(_value), do: nil

  defp normalize_breaker_outcome(:success), do: :success
  defp normalize_breaker_outcome(:failure), do: :failure
  defp normalize_breaker_outcome(:ignore), do: :ignore
  defp normalize_breaker_outcome(true), do: :success
  defp normalize_breaker_outcome(false), do: :failure
  defp normalize_breaker_outcome(_value), do: :ignore

  defp normalize_telemetry(value) when is_map(value), do: value
  defp normalize_telemetry(_value), do: %{}
end
