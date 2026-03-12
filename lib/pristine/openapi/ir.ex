defmodule Pristine.OpenAPI.IR do
  @moduledoc """
  Canonical intermediate representation for OpenAPI-derived generator output.
  """

  alias Pristine.OpenAPI.IR.Operation
  alias Pristine.OpenAPI.IR.Schema
  alias Pristine.OpenAPI.IR.SecurityScheme
  alias Pristine.OpenAPI.IR.SourceContext

  @type source_context_key :: {atom(), String.t()}

  @type t :: %__MODULE__{
          operations: [Operation.t()],
          schemas: [Schema.t()],
          security_schemes: %{optional(String.t()) => SecurityScheme.t()},
          source_contexts: %{optional(source_context_key()) => SourceContext.t()}
        }

  @enforce_keys [:operations, :schemas, :security_schemes, :source_contexts]
  defstruct operations: [], schemas: [], security_schemes: %{}, source_contexts: %{}
end
