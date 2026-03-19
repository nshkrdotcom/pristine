defmodule Pristine.Adapters.Transport.Finch do
  @moduledoc """
  Finch-backed transport adapter.
  """

  @behaviour Pristine.Ports.Transport

  alias Pristine.Core.{Context, Request, Response}

  @impl true
  def send(%Request{} = request, %Context{} = context) do
    finch = Keyword.get(context.transport_opts, :finch, Finch)
    pool = resolve_pool(request.metadata, context.transport_opts, finch)

    case normalize_method(request.method) do
      {:ok, method} ->
        headers = Enum.into(request.headers, [])
        req = Finch.build(method, request.url, headers, request.body)
        finch_opts = send_opts(request, context)

        case Finch.request(req, pool, finch_opts) do
          {:ok, response} ->
            {:ok,
             %Response{
               status: response.status,
               headers: Enum.into(response.headers, %{}),
               body: response.body
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  defp normalize_method(method) when is_atom(method) do
    {:ok, method}
  end

  defp normalize_method(method) when is_binary(method) do
    case String.downcase(method) do
      "get" -> {:ok, :get}
      "post" -> {:ok, :post}
      "put" -> {:ok, :put}
      "patch" -> {:ok, :patch}
      "delete" -> {:ok, :delete}
      "head" -> {:ok, :head}
      "options" -> {:ok, :options}
      _ -> {:error, :invalid_method}
    end
  end

  defp normalize_method(_), do: {:error, :invalid_method}

  defp send_opts(%Request{} = request, %Context{} = context) do
    request_timeout = Map.get(request.metadata, :timeout)

    context.transport_opts
    |> maybe_override_timeout(request_timeout)
    |> finch_opts()
  end

  defp maybe_override_timeout(opts, timeout) when is_integer(timeout) and timeout >= 0 do
    Keyword.put(opts, :timeout, timeout)
  end

  defp maybe_override_timeout(opts, _timeout), do: opts

  defp finch_opts(opts) do
    timeout = Keyword.get(opts, :timeout)
    receive_timeout = Keyword.get(opts, :receive_timeout, timeout)

    opts
    |> Keyword.drop([:timeout, :receive_timeout, :pool_name, :finch])
    |> maybe_put_receive_timeout(receive_timeout)
  end

  defp maybe_put_receive_timeout(opts, nil), do: opts
  defp maybe_put_receive_timeout(opts, timeout), do: Keyword.put(opts, :receive_timeout, timeout)

  defp resolve_pool(metadata, transport_opts, finch)
       when is_map(metadata) and is_list(transport_opts) do
    metadata
    |> Map.get(:pool_name)
    |> fallback_pool(Keyword.get(transport_opts, :pool_name))
    |> fallback_pool(finch)
  end

  defp fallback_pool(nil, fallback), do: fallback
  defp fallback_pool(pool, _fallback), do: pool
end
