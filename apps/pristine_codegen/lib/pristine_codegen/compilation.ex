defmodule PristineCodegen.Compilation do
  @moduledoc """
  Result returned by the shared provider compiler.
  """

  alias PristineCodegen.ProviderIR
  alias PristineCodegen.RenderedFile

  @type t :: %__MODULE__{
          provider_module: module(),
          provider_ir: ProviderIR.t(),
          rendered_files: [RenderedFile.t()],
          artifact_files: [RenderedFile.t()],
          paths: map()
        }

  @enforce_keys [:provider_module, :provider_ir, :rendered_files, :artifact_files, :paths]
  defstruct [:provider_module, :provider_ir, :rendered_files, :artifact_files, :paths]

  @spec all_files(t()) :: [RenderedFile.t()]
  def all_files(%__MODULE__{} = compilation) do
    compilation.rendered_files ++ compilation.artifact_files
  end
end
