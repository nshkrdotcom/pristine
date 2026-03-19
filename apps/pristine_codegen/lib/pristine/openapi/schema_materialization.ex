defmodule Pristine.OpenAPI.SchemaMaterialization do
  @moduledoc false

  alias OpenAPI.Processor.Schema, as: ProcessedSchema

  @spec materialized_typed_map?(term(), term(), term()) :: boolean()
  def materialized_typed_map?(
        %ProcessedSchema{
          context: [{:response, response_module, _, _, _}],
          output_format: :typed_map
        },
        file_module,
        _schemas_by_ref
      )
      when response_module == file_module,
      do: true

  def materialized_typed_map?(
        %ProcessedSchema{
          module_name: file_module,
          output_format: :typed_map,
          type_name: :t
        },
        file_module,
        _schemas_by_ref
      ),
      do: true

  def materialized_typed_map?(
        %ProcessedSchema{context: [{:field, parent_ref, _}], output_format: :typed_map},
        file_module,
        schemas_by_ref
      )
      when is_map(schemas_by_ref) do
    materialized_typed_map_parent?(parent_ref, file_module, schemas_by_ref)
  end

  def materialized_typed_map?(_schema, _file_module, _schemas_by_ref), do: false

  defp materialized_typed_map_parent?(parent_ref, file_module, schemas_by_ref) do
    case Map.get(schemas_by_ref, parent_ref) do
      %ProcessedSchema{
        context: [{:response, response_module, _, _, _}],
        output_format: :typed_map
      }
      when response_module == file_module ->
        true

      %ProcessedSchema{
        module_name: ^file_module,
        output_format: :typed_map,
        type_name: :t
      } ->
        true

      %ProcessedSchema{context: [{:field, next_parent_ref, _}], output_format: :typed_map} ->
        materialized_typed_map_parent?(next_parent_ref, file_module, schemas_by_ref)

      _other ->
        false
    end
  end
end
