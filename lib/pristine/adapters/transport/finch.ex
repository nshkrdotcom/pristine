defmodule Pristine.Adapters.Transport.Finch do
  @moduledoc """
  Finch-backed transport adapter.
  """

  @behaviour Pristine.Ports.Transport
  @behaviour Pristine.Ports.HTTPTransport

  alias Pristine.Core.{Context, Request, Response}

  @impl true
  def send(%Request{} = request, %Context{} = context) do
    finch = Keyword.get(context.transport_opts, :finch, Finch)

    pool =
      Map.get(
        request.metadata,
        :pool_name,
        Keyword.get(context.transport_opts, :pool_name, finch)
      )

    case normalize_method(request.method) do
      {:ok, method} ->
        headers = Enum.into(request.headers, [])
        req = Finch.build(method, request.url, headers, request.body)

        case Finch.request(req, pool) do
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

  @impl true
  def request(method, url, headers, body, opts) do
    finch = Keyword.get(opts, :finch, Finch)
    pool = Keyword.get(opts, :pool_name, finch)
    request = Finch.build(method, url, headers, body)
    finch_opts = finch_opts(opts)

    case Finch.request(request, pool, finch_opts) do
      {:ok, %Finch.Response{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, %{status: status, headers: resp_headers, body: resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream(method, url, headers, body, opts) do
    with {:ok, %{body: resp_body}} <- request(method, url, headers, body, opts) do
      {:ok, Stream.concat([[resp_body]])}
    end
  end

  defp finch_opts(opts) do
    timeout = Keyword.get(opts, :timeout)
    receive_timeout = Keyword.get(opts, :receive_timeout, timeout)

    opts
    |> Keyword.drop([:timeout, :receive_timeout, :pool_name, :finch])
    |> maybe_put_receive_timeout(receive_timeout)
  end

  defp maybe_put_receive_timeout(opts, nil), do: opts
  defp maybe_put_receive_timeout(opts, timeout), do: Keyword.put(opts, :receive_timeout, timeout)
end
