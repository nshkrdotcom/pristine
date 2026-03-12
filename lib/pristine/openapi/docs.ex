defmodule Pristine.OpenAPI.Docs do
  @moduledoc """
  Builds a JSON-ready docs manifest for OpenAPI bridge results.
  """

  alias Pristine.OpenAPI.DocComposer
  alias Pristine.OpenAPI.IR
  alias Pristine.OpenAPI.IR.CodeSample
  alias Pristine.OpenAPI.IR.Operation
  alias Pristine.OpenAPI.IR.Schema
  alias Pristine.OpenAPI.IR.SecurityScheme
  alias Pristine.OpenAPI.IR.SourceContext

  @spec build(map(), IR.t()) :: map()
  def build(generator_state, %IR{} = ir) when is_map(generator_state) do
    profile = generator_state |> Map.get(:call, %{}) |> Map.get(:profile)
    base_module = profile_base_module(profile)
    ref_labels = schema_ref_labels(ir.schemas, base_module)

    manifest = %{
      profile: profile && Atom.to_string(profile),
      generated_files:
        generator_state
        |> Map.get(:files, [])
        |> Enum.map(&Map.get(&1, :location))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort(),
      operations: Enum.map(ir.operations, &operation_entry(&1, base_module, ref_labels)),
      modules:
        generator_state
        |> Map.get(:files, [])
        |> Enum.sort_by(fn file -> full_module_name(Map.get(file, :module), base_module) end)
        |> Enum.map(&module_entry(&1, base_module, ir.source_contexts)),
      schemas:
        ir.schemas
        |> Enum.sort_by(&schema_sort_key(&1, base_module, ref_labels))
        |> Enum.uniq_by(&Map.fetch!(ref_labels, &1.ref))
        |> Enum.map(&schema_entry(&1, base_module, ref_labels)),
      security_schemes:
        ir.security_schemes
        |> Enum.map(fn {name, scheme} -> {name, security_scheme_entry(scheme)} end)
        |> Map.new(),
      source_contexts:
        ir.source_contexts
        |> Map.values()
        |> Enum.sort_by(fn source_context -> {source_context.method, source_context.path} end)
        |> Enum.map(&source_context_entry/1)
    }

    stringify_keys(manifest)
  end

  defp operation_entry(%Operation{} = operation, base_module, ref_labels) do
    composed = DocComposer.operation(operation, source_context: operation.source_context)

    Map.merge(composed, %{
      module: full_module_name(operation.module_name, base_module),
      function: Atom.to_string(operation.function_name),
      method: Atom.to_string(operation.method),
      path: operation.path,
      tags: operation.tags,
      security: operation.security,
      request_body: composed.request_body,
      query_params: Enum.map(operation.query_params, &param_entry(&1, ref_labels)),
      responses: composed.responses,
      external_docs: composed.external_docs,
      source_context: source_context_entry(operation.source_context),
      code_samples: Enum.map(operation.code_samples, &code_sample_entry/1),
      extensions: operation.extensions
    })
  end

  defp module_entry(file, base_module, source_contexts) do
    composed = DocComposer.module(file, source_contexts: source_contexts)

    %{
      module: full_module_name(Map.get(file, :module), base_module),
      doc: composed.doc,
      operations:
        Map.get(file, :operations, [])
        |> Enum.map(&Atom.to_string(Map.get(&1, :function_name))),
      schema_types:
        Map.get(file, :schemas, [])
        |> Enum.map(fn schema -> Atom.to_string(Map.get(schema, :type_name)) end)
        |> Enum.sort()
    }
  end

  defp schema_entry(%Schema{} = schema, base_module, ref_labels) do
    composed = DocComposer.schema(schema)

    Map.merge(composed, %{
      module: full_module_name(schema.module_name, base_module),
      type: Atom.to_string(schema.type_name),
      ref: Map.fetch!(ref_labels, schema.ref),
      output_format: schema.output_format && Atom.to_string(schema.output_format),
      contexts: Enum.map(schema.contexts, &context_entry(&1, ref_labels)),
      deprecated: schema.deprecated,
      example: normalize_manifest_value(schema.example, ref_labels),
      examples: normalize_manifest_value(schema.examples, ref_labels),
      external_docs: normalize_manifest_value(schema.external_docs, ref_labels),
      extensions: normalize_manifest_value(schema.extensions, ref_labels),
      fields: normalize_manifest_value(composed.fields, ref_labels)
    })
  end

  defp security_scheme_entry(%SecurityScheme{} = scheme) do
    %{
      name: scheme.name,
      type: scheme.type,
      scheme: scheme.scheme,
      description: scheme.description,
      details: scheme.details
    }
  end

  defp source_context_entry(nil), do: nil

  defp source_context_entry(%SourceContext{} = source_context) do
    %{
      method: Atom.to_string(source_context.method),
      path: source_context.path,
      title: source_context.title,
      summary: source_context.summary,
      description: source_context.description,
      url: source_context.url,
      code_samples: Enum.map(source_context.code_samples, &code_sample_entry/1),
      metadata: source_context.metadata
    }
  end

  defp param_entry(param, ref_labels) do
    %{
      name: param.name,
      location: param.location && Atom.to_string(param.location),
      description: param.description,
      required: param.required,
      deprecated: param.deprecated,
      example: param.example,
      examples: param.examples,
      style: param.style && Atom.to_string(param.style),
      explode: param.explode,
      value_type:
        normalize_manifest_value(DocComposer.json_friendly_type(param.value_type), ref_labels),
      extensions: param.extensions
    }
  end

  defp code_sample_entry(%CodeSample{} = code_sample) do
    %{
      language: code_sample.language,
      label: code_sample.label,
      source: code_sample.source,
      metadata: code_sample.metadata
    }
  end

  defp schema_ref_labels(schemas, base_module) do
    schemas_by_ref = Map.new(schemas, &{&1.ref, &1})

    Enum.into(schemas, %{}, fn %Schema{ref: ref} = schema ->
      {ref, schema_ref_label(schema, base_module, schemas_by_ref)}
    end)
  end

  defp schema_ref_label(%Schema{} = schema, base_module, schemas_by_ref) do
    [
      full_module_name(schema.module_name, base_module) || "anonymous_schema",
      Atom.to_string(schema.type_name),
      (schema.output_format && Atom.to_string(schema.output_format)) || "none",
      schema_signature_hash(schema, schemas_by_ref)
    ]
    |> Enum.join(".")
  end

  defp schema_signature_hash(schema, schemas_by_ref) do
    schema
    |> schema_signature(schemas_by_ref, MapSet.new())
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp schema_sort_key(schema, base_module, ref_labels) do
    {
      full_module_name(schema.module_name, base_module),
      Atom.to_string(schema.type_name),
      schema.output_format && Atom.to_string(schema.output_format),
      Map.fetch!(ref_labels, schema.ref),
      Enum.map(schema.contexts, &context_entry(&1, ref_labels)),
      schema.title,
      schema.description
    }
  end

  defp context_entry(context, ref_labels) do
    context
    |> normalize_context_term(ref_labels)
    |> inspect()
  end

  defp normalize_context_term(reference, ref_labels) when is_reference(reference) do
    Map.get(ref_labels, reference, "<schema_ref>")
  end

  defp normalize_context_term(tuple, ref_labels) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize_context_term(&1, ref_labels))
    |> List.to_tuple()
  end

  defp normalize_context_term(list, ref_labels) when is_list(list) do
    Enum.map(list, &normalize_context_term(&1, ref_labels))
  end

  defp normalize_context_term(map, ref_labels) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      {normalize_context_term(key, ref_labels), normalize_context_term(value, ref_labels)}
    end)
  end

  defp normalize_context_term(value, _ref_labels), do: value

  defp normalize_manifest_value(reference, ref_labels) when is_reference(reference) do
    Map.get(ref_labels, reference, "<schema_ref>")
  end

  defp normalize_manifest_value(%_{} = struct, ref_labels) do
    struct
    |> Map.from_struct()
    |> normalize_manifest_value(ref_labels)
  end

  defp normalize_manifest_value(map, ref_labels) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      {normalize_manifest_value(key, ref_labels), normalize_manifest_value(value, ref_labels)}
    end)
  end

  defp normalize_manifest_value(list, ref_labels) when is_list(list) do
    Enum.map(list, &normalize_manifest_value(&1, ref_labels))
  end

  defp normalize_manifest_value(tuple, ref_labels) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize_manifest_value(&1, ref_labels))
    |> List.to_tuple()
  end

  defp normalize_manifest_value(value, _ref_labels), do: value

  defp schema_signature(%Schema{} = schema, schemas_by_ref, seen) do
    seen =
      case schema.ref do
        ref when is_reference(ref) -> MapSet.put(seen, ref)
        _other -> seen
      end

    [
      module_name: full_module_name(schema.module_name, nil),
      type_name: Atom.to_string(schema.type_name),
      output_format: schema.output_format && Atom.to_string(schema.output_format),
      title: schema.title,
      description: schema.description,
      fields:
        schema.fields
        |> Enum.map(&field_signature(&1, schemas_by_ref, seen))
        |> Enum.sort()
    ]
  end

  defp field_signature(field, schemas_by_ref, seen) do
    [
      name: field.name,
      type: normalize_signature_term(field.type, schemas_by_ref, seen),
      required: field.required,
      nullable: field.nullable,
      read_only: field.read_only,
      write_only: field.write_only
    ]
  end

  defp normalize_signature_term(reference, schemas_by_ref, seen) when is_reference(reference) do
    case Map.get(schemas_by_ref, reference) do
      %Schema{} = schema ->
        if MapSet.member?(seen, reference),
          do: {:schema_ref, shallow_schema_identity(schema)},
          else: {:schema_ref, shallow_schema_identity(schema)}

      nil ->
        {:schema_ref, "missing"}
    end
  end

  defp normalize_signature_term(%_{} = struct, schemas_by_ref, seen),
    do: struct |> Map.from_struct() |> normalize_signature_term(schemas_by_ref, seen)

  defp normalize_signature_term(map, schemas_by_ref, seen) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      {normalize_signature_term(key, schemas_by_ref, seen),
       normalize_signature_term(value, schemas_by_ref, seen)}
    end)
    |> Enum.sort()
  end

  defp normalize_signature_term(tuple, schemas_by_ref, seen) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize_signature_term(&1, schemas_by_ref, seen))
    |> List.to_tuple()
  end

  defp normalize_signature_term(list, schemas_by_ref, seen) when is_list(list),
    do: Enum.map(list, &normalize_signature_term(&1, schemas_by_ref, seen))

  defp normalize_signature_term(atom, _schemas_by_ref, _seen) when is_atom(atom),
    do: Atom.to_string(atom)

  defp normalize_signature_term(value, _schemas_by_ref, _seen), do: value

  defp shallow_schema_identity(%Schema{} = schema) do
    [
      module_name: full_module_name(schema.module_name, nil),
      type_name: Atom.to_string(schema.type_name),
      output_format: schema.output_format && Atom.to_string(schema.output_format),
      title: schema.title,
      description: schema.description,
      field_names: schema.fields |> Enum.map(& &1.name) |> Enum.sort()
    ]
  end

  defp profile_base_module(nil), do: nil

  defp profile_base_module(profile) do
    Application.get_env(:oapi_generator, profile, [])
    |> Keyword.get(:output, [])
    |> Keyword.get(:base_module)
  end

  defp full_module_name(nil, _base_module), do: nil
  defp full_module_name(module, nil), do: inspect(module)

  defp full_module_name(module, base_module) do
    module
    |> then(&Module.concat([base_module, &1]))
    |> inspect()
  end

  defp stringify_keys(%_{} = struct), do: struct |> Map.from_struct() |> stringify_keys()

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
