defmodule Pristine.OpenAPI.Result do
  @moduledoc """
  Canonical result returned by `Pristine.OpenAPI.Bridge.run/3`.
  """

  alias Pristine.OpenAPI.Docs
  alias Pristine.OpenAPI.IR
  alias Pristine.OpenAPI.Mapper

  @type source_context_key :: {atom(), String.t()}

  @type t :: %__MODULE__{
          ir: IR.t(),
          source_contexts: %{optional(source_context_key()) => IR.SourceContext.t()},
          docs_manifest: map()
        }

  @enforce_keys [:ir, :source_contexts, :docs_manifest]
  defstruct [:ir, :source_contexts, :docs_manifest]

  @spec from_generator_state(map(), keyword()) :: t()
  def from_generator_state(generator_state, opts \\ [])
      when is_map(generator_state) and is_list(opts) do
    ir = Mapper.to_ir(generator_state, opts)

    %__MODULE__{
      ir: ir,
      source_contexts: ir.source_contexts,
      docs_manifest: Docs.build(generator_state, ir)
    }
  end
end
