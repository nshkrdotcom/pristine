defmodule Pristine.OpenAPI.IR.Operation do
  @moduledoc """
  Canonical operation metadata mapped from the generator state.
  """

  alias Pristine.OpenAPI.IR.CodeSample
  alias Pristine.OpenAPI.IR.SourceContext

  @type request_body_doc :: %{
          description: String.t() | nil,
          required: boolean(),
          content_types: [String.t()]
        }

  @type response_doc :: %{
          status: integer() | String.t() | atom(),
          description: String.t() | nil,
          content_types: [String.t()]
        }

  @type param :: %{
          name: String.t(),
          location: atom() | nil,
          description: String.t() | nil,
          required: boolean(),
          deprecated: boolean(),
          example: term(),
          examples: term(),
          style: atom() | nil,
          explode: boolean(),
          value_type: term(),
          extensions: map()
        }

  @type t :: %__MODULE__{
          module_name: module(),
          function_name: atom(),
          method: atom(),
          path: String.t(),
          summary: String.t() | nil,
          description: String.t() | nil,
          deprecated: boolean(),
          external_docs: map() | nil,
          tags: [String.t()],
          security: [map()] | nil,
          request_body: request_body_doc() | nil,
          query_params: [param()],
          path_params: [param()],
          header_params: [param()],
          response_docs: [response_doc()],
          extensions: map(),
          source_context: SourceContext.t() | nil,
          code_samples: [CodeSample.t()]
        }

  @enforce_keys [
    :module_name,
    :function_name,
    :method,
    :path,
    :summary,
    :description,
    :deprecated,
    :external_docs,
    :tags,
    :security,
    :request_body,
    :query_params,
    :path_params,
    :header_params,
    :response_docs,
    :extensions,
    :source_context,
    :code_samples
  ]
  defstruct [
    :module_name,
    :function_name,
    :method,
    :path,
    :summary,
    :description,
    :deprecated,
    :external_docs,
    :tags,
    :security,
    :request_body,
    :query_params,
    :path_params,
    :header_params,
    :response_docs,
    :extensions,
    :source_context,
    :code_samples
  ]
end
