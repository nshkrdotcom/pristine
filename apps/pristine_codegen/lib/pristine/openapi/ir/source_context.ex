defmodule Pristine.OpenAPI.IR.SourceContext do
  @moduledoc """
  Canonical provider-neutral source context keyed by `{method, path}`.
  """

  alias Pristine.OpenAPI.IR.CodeSample

  @type t :: %__MODULE__{
          method: atom(),
          path: String.t(),
          title: String.t() | nil,
          summary: String.t() | nil,
          description: String.t() | nil,
          url: String.t() | nil,
          code_samples: [CodeSample.t()],
          metadata: map()
        }

  @enforce_keys [:method, :path, :title, :summary, :description, :url, :code_samples, :metadata]
  defstruct [:method, :path, :title, :summary, :description, :url, :code_samples, :metadata]
end
