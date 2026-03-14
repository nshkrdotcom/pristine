defmodule Pristine.Ports.ResultClassifier do
  @moduledoc """
  Classification boundary for normalized request outcomes.
  """

  alias Pristine.Core.{Context, EndpointMetadata, ResultClassification}

  @callback classify(term(), EndpointMetadata.t(), Context.t(), keyword()) ::
              ResultClassification.t() | map()
end
