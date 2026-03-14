defmodule Pristine.SDK.OpenAPI.Runtime do
  @moduledoc """
  SDK-facing runtime helpers for generated OpenAPI schema modules.
  """

  alias Pristine.OpenAPI.Runtime, as: RuntimeOpenAPI

  @type openapi_field :: RuntimeOpenAPI.openapi_field()

  @spec build_schema([openapi_field()]) :: Sinter.Schema.t()
  defdelegate build_schema(fields), to: RuntimeOpenAPI

  @spec decode_module_type(module(), atom(), term()) :: {:ok, term()} | {:error, term()}
  defdelegate decode_module_type(module, type, data), to: RuntimeOpenAPI

  @spec resolve_schema(term(), map()) :: term() | nil
  defdelegate resolve_schema(ref, type_schemas), to: RuntimeOpenAPI

  @spec materialize(term(), term(), map()) :: term()
  defdelegate materialize(ref, data, type_schemas), to: RuntimeOpenAPI
end
