defmodule Pristine.Ports.ResultClassifier do
  @moduledoc """
  Classification boundary for normalized request outcomes.
  """

  alias Pristine.Core.{Context, ResultClassification}
  alias Pristine.Manifest.Endpoint

  @callback classify(term(), Endpoint.t(), Context.t(), keyword()) ::
              ResultClassification.t() | map()
end
