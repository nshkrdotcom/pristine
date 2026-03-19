defmodule Pristine.OpenAPI.IR.CodeSample do
  @moduledoc """
  Canonical code sample attached to an OpenAPI operation or source context.
  """

  @type t :: %__MODULE__{
          language: String.t() | nil,
          label: String.t() | nil,
          source: String.t() | nil,
          metadata: map()
        }

  @enforce_keys [:language, :label, :source, :metadata]
  defstruct language: nil, label: nil, source: nil, metadata: %{}
end
