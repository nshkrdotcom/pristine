defmodule PristineCodegen.Source.Dataset do
  @moduledoc """
  Bounded source-plugin payload merged into a provider definition before
  normalization.
  """

  @type t :: %__MODULE__{
          operations: [map()],
          schemas: [map()],
          auth_policies: [map()],
          pagination_policies: [map()],
          docs_inventory: map(),
          fingerprints: map()
        }

  defstruct operations: [],
            schemas: [],
            auth_policies: [],
            pagination_policies: [],
            docs_inventory: %{},
            fingerprints: %{}
end
