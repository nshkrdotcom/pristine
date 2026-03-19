defmodule Pristine.Ports.AdmissionControl do
  @moduledoc """
  Admission-control boundary for optional high-throughput request shaping.
  """

  @callback with_admission((-> term()), keyword()) :: term()
  @callback set_backoff(non_neg_integer(), keyword()) :: :ok

  @optional_callbacks [set_backoff: 2]
end
