defmodule Pristine.Adapters.RateLimit.BackoffWindow do
  @moduledoc """
  Rate limit adapter backed by Foundation.RateLimit.BackoffWindow.
  """

  @behaviour Pristine.Ports.RateLimit

  alias Foundation.RateLimit.BackoffWindow

  @impl true
  def within_limit(fun, opts) when is_function(fun, 0) do
    key = Keyword.get(opts, :key, :default)
    registry = resolve_registry(opts)
    limiter = BackoffWindow.for_key(registry, key)

    if BackoffWindow.should_backoff?(limiter, opts) do
      BackoffWindow.wait(limiter, opts)
    end

    fun.()
  end

  @doc """
  Set a backoff window for a key.
  """
  @spec backoff(term(), non_neg_integer(), keyword()) :: :ok
  def backoff(key, duration_ms, opts \\ []) do
    registry = resolve_registry(opts)
    limiter = BackoffWindow.for_key(registry, key)
    BackoffWindow.set(limiter, duration_ms, opts)
  end

  @impl true
  def for_key(key, opts \\ []) do
    registry = resolve_registry(opts)
    BackoffWindow.for_key(registry, key)
  end

  @impl true
  def wait(limiter, opts \\ []) do
    BackoffWindow.wait(limiter, opts)
  end

  @impl true
  def clear(limiter) do
    BackoffWindow.clear(limiter)
  end

  @impl true
  def set(limiter, duration_ms, opts \\ []) do
    BackoffWindow.set(limiter, duration_ms, opts)
  end

  defp resolve_registry(opts) do
    case Keyword.get(opts, :registry) do
      nil ->
        ensure_default_registry()

      registry ->
        ensure_registry(registry)
    end
  end

  defp ensure_default_registry do
    registry = BackoffWindow.default_registry()
    ensure_registry(registry, default: true)
  end

  defp ensure_registry(registry, opts \\ []) do
    if registry_valid?(registry) do
      registry
    else
      new_registry = create_registry(registry)

      if Keyword.get(opts, :default, false) do
        :persistent_term.put(
          {Foundation.RateLimit.BackoffWindow, :default_registry},
          new_registry
        )
      end

      new_registry
    end
  end

  defp create_registry(registry) when is_atom(registry) do
    BackoffWindow.new_registry(name: registry)
  end

  defp create_registry(_registry) do
    BackoffWindow.new_registry()
  end

  defp registry_valid?(registry) when is_reference(registry) do
    case :lists.search(fn tid -> tid == registry end, :ets.all()) do
      {:value, tid} -> registry_info_valid?(tid)
      false -> false
    end
  end

  defp registry_valid?(registry) when is_atom(registry) do
    case :ets.whereis(registry) do
      :undefined -> false
      _ -> true
    end
  end

  defp registry_valid?(_registry), do: false

  defp registry_info_valid?(registry) do
    case :ets.info(registry) do
      :undefined ->
        false

      info ->
        case Keyword.get(info, :heir, :none) do
          :none -> false
          {heir_pid, _} -> Process.alive?(heir_pid)
          heir_pid when is_pid(heir_pid) -> Process.alive?(heir_pid)
          _ -> false
        end
    end
  rescue
    ArgumentError -> false
  end
end
