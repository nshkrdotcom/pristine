defmodule Pristine.OpenAPI.IR.Schema do
  @moduledoc """
  Canonical schema metadata mapped from the generator state.
  """

  alias Pristine.OpenAPI.IR.Field

  @type t :: %__MODULE__{
          ref: term(),
          module_name: module(),
          type_name: atom(),
          title: String.t() | nil,
          description: String.t() | nil,
          deprecated: boolean(),
          example: term(),
          examples: term(),
          external_docs: map() | nil,
          extensions: map(),
          output_format: atom() | nil,
          contexts: [tuple()],
          fields: [Field.t()]
        }

  @enforce_keys [
    :ref,
    :module_name,
    :type_name,
    :title,
    :description,
    :deprecated,
    :example,
    :examples,
    :external_docs,
    :extensions,
    :output_format,
    :contexts,
    :fields
  ]
  defstruct [
    :ref,
    :module_name,
    :type_name,
    :title,
    :description,
    :deprecated,
    :example,
    :examples,
    :external_docs,
    :extensions,
    :output_format,
    :contexts,
    :fields
  ]
end
