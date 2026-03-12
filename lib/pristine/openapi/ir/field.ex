defmodule Pristine.OpenAPI.IR.Field do
  @moduledoc """
  Canonical field metadata for an OpenAPI schema.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          type: term(),
          description: String.t() | nil,
          default: term(),
          required: boolean(),
          nullable: boolean(),
          deprecated: boolean(),
          read_only: boolean(),
          write_only: boolean(),
          example: term(),
          examples: term(),
          external_docs: map() | nil,
          extensions: map()
        }

  @enforce_keys [
    :name,
    :type,
    :description,
    :default,
    :required,
    :nullable,
    :deprecated,
    :read_only,
    :write_only,
    :example,
    :examples,
    :external_docs,
    :extensions
  ]
  defstruct [
    :name,
    :type,
    :description,
    :default,
    :required,
    :nullable,
    :deprecated,
    :read_only,
    :write_only,
    :example,
    :examples,
    :external_docs,
    :extensions
  ]
end
