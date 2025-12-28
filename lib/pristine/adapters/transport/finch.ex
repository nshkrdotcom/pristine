defmodule Pristine.Adapters.Transport.Finch do
  @moduledoc """
  Finch-backed transport adapter.
  """

  @behaviour Pristine.Ports.Transport

  alias Pristine.Core.{Context, Request, Response}

  @impl true
  def send(%Request{} = request, %Context{} = context) do
    finch = Keyword.get(context.transport_opts, :finch, Finch)

    case normalize_method(request.method) do
      {:ok, method} ->
        headers = Enum.into(request.headers, [])
        req = Finch.build(method, request.url, headers, request.body)

        case Finch.request(req, finch) do
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
end
