defmodule Pristine.OpenAPI.IR.SecurityScheme do
  @moduledoc """
  Canonical security scheme metadata preserved from the OpenAPI spec.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          type: String.t() | nil,
          scheme: String.t() | nil,
          description: String.t() | nil,
          details: map()
        }

  @enforce_keys [:name, :type, :scheme, :description, :details]
  defstruct [:name, :type, :scheme, :description, :details]
end
