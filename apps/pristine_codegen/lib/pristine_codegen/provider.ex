defmodule PristineCodegen.Provider do
  @moduledoc """
  Provider definition contract consumed by the shared compiler.
  """

  @callback definition(keyword()) :: map()
  @callback paths(keyword()) :: map()
  @callback source_plugins() :: [module()]
  @callback auth_plugins() :: [module()]
  @callback pagination_plugins() :: [module()]
  @callback docs_plugins() :: [module()]
  @callback refresh(keyword()) :: term()

  @optional_callbacks refresh: 1

  @spec definition(module(), keyword()) :: map()
  def definition(provider_module, opts) when is_atom(provider_module) and is_list(opts) do
    provider_module.definition(opts)
  end

  @spec paths(module(), keyword()) :: map()
  def paths(provider_module, opts) when is_atom(provider_module) and is_list(opts) do
    provider_module.paths(opts)
  end

  @spec source_plugins(module()) :: [module()]
  def source_plugins(provider_module) when is_atom(provider_module) do
    plugin_list(provider_module, :source_plugins)
  end

  @spec auth_plugins(module()) :: [module()]
  def auth_plugins(provider_module) when is_atom(provider_module) do
    plugin_list(provider_module, :auth_plugins)
  end

  @spec pagination_plugins(module()) :: [module()]
  def pagination_plugins(provider_module) when is_atom(provider_module) do
    plugin_list(provider_module, :pagination_plugins)
  end

  @spec docs_plugins(module()) :: [module()]
  def docs_plugins(provider_module) when is_atom(provider_module) do
    plugin_list(provider_module, :docs_plugins)
  end

  @spec refresh(module(), keyword()) :: term()
  def refresh(provider_module, opts) when is_atom(provider_module) and is_list(opts) do
    if function_exported?(provider_module, :refresh, 1) do
      provider_module.refresh(opts)
    else
      :ok
    end
  end

  defp plugin_list(provider_module, callback) do
    if function_exported?(provider_module, callback, 0) do
      apply(provider_module, callback, [])
    else
      []
    end
  end
end
