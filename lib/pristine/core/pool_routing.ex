defmodule Pristine.Core.PoolRouting do
  @moduledoc false

  alias Pristine.Core.Context

  @type pool_type :: atom() | String.t()

  @spec resolve_type(map(), keyword()) :: pool_type()
  def resolve_type(endpoint, opts) do
    opts
    |> Keyword.get(
      :pool_type,
      Map.get(endpoint, :resource) || Map.get(endpoint, "resource") || :default
    )
    |> normalize_type()
  end

  @spec resolve_name(Context.t(), pool_type()) :: atom() | nil
  def resolve_name(
        %Context{pool_manager: manager, pool_base: pool_base, base_url: base_url},
        pool_type
      )
      when is_atom(pool_type) and is_atom(manager) and not is_nil(manager) and is_atom(pool_base) and
             is_binary(base_url) do
    manager.resolve_pool_name(pool_base, base_url, pool_type)
  end

  def resolve_name(%Context{pool_base: pool_base}, _pool_type) when is_atom(pool_base),
    do: pool_base

  def resolve_name(_context, _pool_type), do: nil

  @spec normalize_type(term()) :: pool_type()
  def normalize_type(value) when is_atom(value), do: value
  def normalize_type(value) when is_binary(value), do: value
  def normalize_type(_value), do: :default
end
