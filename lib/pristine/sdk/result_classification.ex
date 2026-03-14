defmodule Pristine.SDK.ResultClassification do
  @moduledoc """
  SDK-facing request outcome classification contract.
  """

  alias Pristine.Core.ResultClassification, as: RuntimeResultClassification

  @type breaker_outcome :: RuntimeResultClassification.breaker_outcome()
  @type t :: RuntimeResultClassification.t()

  @spec normalize(t() | map() | keyword() | nil) :: t()
  defdelegate normalize(classification), to: RuntimeResultClassification
end
