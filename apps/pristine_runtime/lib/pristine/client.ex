defmodule Pristine.Client do
  @moduledoc """
  Provider-agnostic runtime client used by generated providers and thin facades.
  """

  alias Pristine.Core.Context
  alias Pristine.Profiles.Foundation

  @type runtime_defaults_t :: %{
          retry: module() | nil,
          timeout_ms: non_neg_integer() | nil,
          telemetry: module() | nil,
          serializer: module() | nil,
          stream_transport: module() | nil,
          rate_limiter: module() | nil,
          circuit_breaker: module() | nil
        }

  @type t :: %__MODULE__{
          context: Context.t(),
          base_url: String.t() | nil,
          default_headers: map(),
          default_auth: term(),
          transport: module() | nil,
          runtime_defaults: runtime_defaults_t()
        }

  defstruct context: nil,
            base_url: nil,
            default_headers: %{},
            default_auth: [],
            transport: nil,
            runtime_defaults: %{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    case Keyword.get(opts, :context) do
      %Context{} = context ->
        from_context(context)

      nil ->
        opts
        |> normalize_context_opts()
        |> Context.new()
        |> from_context()

      other ->
        raise ArgumentError,
              "expected :context to be a Pristine.Core.Context, got: #{inspect(other)}"
    end
  end

  @spec foundation(keyword()) :: t()
  def foundation(opts \\ []) when is_list(opts) do
    opts
    |> normalize_context_opts()
    |> Foundation.context()
    |> from_context()
  end

  @spec from_context(Context.t()) :: t()
  def from_context(%Context{} = context) do
    %__MODULE__{
      context: context,
      base_url: context.base_url,
      default_headers: normalize_header_map(context.headers),
      default_auth: context.auth || [],
      transport: context.transport,
      runtime_defaults: %{
        retry: context.retry,
        timeout_ms: context.default_timeout,
        telemetry: context.telemetry,
        serializer: context.serializer,
        stream_transport: context.stream_transport,
        rate_limiter: context.rate_limiter,
        circuit_breaker: context.circuit_breaker
      }
    }
  end

  defp normalize_context_opts(opts) do
    default_headers = Keyword.get(opts, :default_headers)
    default_auth = Keyword.get(opts, :default_auth)
    timeout_ms = Keyword.get(opts, :timeout_ms)

    opts
    |> Keyword.drop([:context, :default_headers, :default_auth, :timeout_ms])
    |> maybe_put(:headers, normalize_header_map(default_headers))
    |> maybe_put(:auth, default_auth)
    |> maybe_put(:default_timeout, timeout_ms)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_header_map(nil), do: %{}

  defp normalize_header_map(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_header_map(headers) when is_list(headers) do
    if Keyword.keyword?(headers) do
      Map.new(headers, fn {key, value} -> {to_string(key), value} end)
    else
      %{}
    end
  end

  defp normalize_header_map(_headers), do: %{}
end
