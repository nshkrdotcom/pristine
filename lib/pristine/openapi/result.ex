defmodule Pristine.OpenAPI.Result do
  @moduledoc """
  Canonical result returned by `Pristine.OpenAPI.Bridge.run/3`.

  The raw generator state is preserved for compatibility, while the canonical
  IR and docs manifest give downstream code a stable, testable surface.
  """

  alias Pristine.OpenAPI.Docs
  alias Pristine.OpenAPI.IR
  alias Pristine.OpenAPI.Mapper

  @type source_context_key :: {atom(), String.t()}

  @type t :: %__MODULE__{
          files: [map()],
          operations: [map()],
          schemas: map(),
          generator_state: map(),
          ir: IR.t(),
          source_contexts: %{optional(source_context_key()) => IR.SourceContext.t()},
          docs_manifest: map()
        }

  @enforce_keys [
    :files,
    :operations,
    :schemas,
    :generator_state,
    :ir,
    :source_contexts,
    :docs_manifest
  ]
  defstruct [
    :files,
    :operations,
    :schemas,
    :generator_state,
    :ir,
    :source_contexts,
    :docs_manifest
  ]

  @spec from_generator_state(map(), keyword()) :: t()
  def from_generator_state(generator_state, opts \\ [])
      when is_map(generator_state) and is_list(opts) do
    ir = Mapper.to_ir(generator_state, opts)

    %__MODULE__{
      files: Map.get(generator_state, :files, []),
      operations: Map.get(generator_state, :operations, []),
      schemas: Map.get(generator_state, :schemas, %{}),
      generator_state: generator_state,
      ir: ir,
      source_contexts: ir.source_contexts,
      docs_manifest: Docs.build(generator_state, ir)
    }
  end
end
