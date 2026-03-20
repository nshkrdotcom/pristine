defmodule PristineCodegen do
  @moduledoc """
  Shared provider compiler entrypoint for `ProviderIR`, renderers, and artifact
  verification.
  """

  alias PristineCodegen.Compiler

  @spec compile(module(), keyword()) :: {:ok, PristineCodegen.Compilation.t()}
  def compile(provider_module, opts \\ []) do
    Compiler.compile(provider_module, opts)
  end

  @spec generate(module(), keyword()) :: {:ok, PristineCodegen.Compilation.t()}
  def generate(provider_module, opts \\ []) do
    Compiler.generate(provider_module, opts)
  end

  @spec verify(module(), keyword()) :: :ok | {:error, map()}
  def verify(provider_module, opts \\ []) do
    Compiler.verify(provider_module, opts)
  end

  @spec emit_ir(module(), keyword()) :: {:ok, String.t()}
  def emit_ir(provider_module, opts \\ []) do
    Compiler.emit_ir(provider_module, opts)
  end

  @spec refresh(module(), keyword()) :: {:ok, PristineCodegen.Compilation.t()}
  def refresh(provider_module, opts \\ []) do
    Compiler.refresh(provider_module, opts)
  end
end
