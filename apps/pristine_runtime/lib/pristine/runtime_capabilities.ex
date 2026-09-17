defmodule Pristine.RuntimeCapabilities do
  @moduledoc """
  Provider-neutral discovery for the configured runtime transport contract.

  Capability discovery is fail-closed. A missing callback, absent capability,
  malformed advertisement, or callback failure is reported as `:unverified`.
  Explicit `false`/`:unsupported` is reported as `:unsupported`.

  A capability advertisement is a transport adapter's declared contract. For
  Pristine-owned adapters, `:supported` is only published after Pristine's own
  acceptance tests prove the behavior. Third-party adapter authors remain
  responsible for conformance with their declarations.

  Capability callbacks must be side-effect free and must never return request
  bodies, credentials, headers, or other context secrets.
  """

  alias Pristine.Client
  alias Pristine.Core.Context

  @known_capabilities [:unary_cancellation, :cancellation_cleanup]

  @type capability_status :: :supported | :unsupported | :unverified
  @type capability :: %{
          required(:status) => capability_status(),
          optional(:value) => non_neg_integer()
        }
  @type transport_capabilities :: %{
          required(:adapter) => module() | nil,
          required(:capabilities) => %{optional(atom()) => capability()}
        }

  @doc """
  Inspect the configured unary transport without performing a request.
  """
  @spec transport(Context.t() | Client.t()) :: transport_capabilities()
  def transport(%Client{context: %Context{} = context}), do: transport(context)

  def transport(%Context{transport: adapter} = context) do
    advertised = advertised_capabilities(adapter, context)

    normalized_known =
      Map.new(@known_capabilities, fn capability ->
        {capability, normalize_boolean_capability(Map.get(advertised, capability, :unverified))}
      end)

    normalized_custom =
      advertised
      |> Enum.reduce(%{}, fn
        {capability, value}, acc
        when is_atom(capability) and capability not in @known_capabilities ->
          Map.put(acc, capability, normalize_capability(value))

        _entry, acc ->
          acc
      end)

    %{adapter: adapter, capabilities: Map.merge(normalized_known, normalized_custom)}
  end

  @doc """
  Return true only when a transport positively advertises a capability.
  """
  @spec supported?(Context.t() | Client.t(), atom()) :: boolean()
  def supported?(source, capability) when is_atom(capability) do
    source
    |> transport()
    |> get_in([:capabilities, capability, :status])
    |> Kernel.==(:supported)
  end

  @doc false
  @spec require_transport(Context.t() | Client.t(), [atom()]) :: :ok | {:error, term()}
  def require_transport(source, capabilities) when is_list(capabilities) do
    report = transport(source)

    missing =
      Map.new(capabilities, fn capability ->
        status = get_in(report, [:capabilities, capability, :status]) || :unverified
        {capability, status}
      end)
      |> Map.reject(fn {_capability, status} -> status == :supported end)

    if map_size(missing) == 0 do
      :ok
    else
      {:error, {:unsupported_transport_capabilities, report.adapter, missing}}
    end
  end

  defp advertised_capabilities(adapter, context) when is_atom(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :capabilities, 1) do
      case adapter.capabilities(context) do
        capabilities when is_map(capabilities) -> capabilities
        _other -> %{}
      end
    else
      %{}
    end
  rescue
    _error -> %{}
  catch
    _kind, _reason -> %{}
  end

  defp advertised_capabilities(_adapter, _context), do: %{}

  defp normalize_boolean_capability(true), do: %{status: :supported}
  defp normalize_boolean_capability(:supported), do: %{status: :supported}
  defp normalize_boolean_capability(false), do: %{status: :unsupported}
  defp normalize_boolean_capability(:unsupported), do: %{status: :unsupported}
  defp normalize_boolean_capability(:unverified), do: %{status: :unverified}
  defp normalize_boolean_capability(%{status: :supported}), do: %{status: :supported}
  defp normalize_boolean_capability(%{status: :unsupported}), do: %{status: :unsupported}
  defp normalize_boolean_capability(%{status: :unverified}), do: %{status: :unverified}
  defp normalize_boolean_capability(_other), do: %{status: :unverified}

  defp normalize_capability(true), do: %{status: :supported}
  defp normalize_capability(:supported), do: %{status: :supported}
  defp normalize_capability(false), do: %{status: :unsupported}
  defp normalize_capability(:unsupported), do: %{status: :unsupported}
  defp normalize_capability(:unverified), do: %{status: :unverified}

  defp normalize_capability(%{status: :supported, value: value})
       when is_integer(value) and value >= 0,
       do: %{status: :supported, value: value}

  defp normalize_capability(%{status: :supported}), do: %{status: :supported}
  defp normalize_capability(%{status: :unsupported}), do: %{status: :unsupported}
  defp normalize_capability(%{status: :unverified}), do: %{status: :unverified}

  defp normalize_capability({:supported, value}) when is_integer(value) and value >= 0,
    do: %{status: :supported, value: value}

  defp normalize_capability(value) when is_integer(value) and value >= 0,
    do: %{status: :supported, value: value}

  defp normalize_capability(_other), do: %{status: :unverified}
end
