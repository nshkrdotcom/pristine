defmodule Pristine.Adapters.Transport.Finch do
  @moduledoc """
  Compatibility-named unary HTTP transport adapter backed by the Execution Plane.
  """

  @behaviour Pristine.Ports.Transport

  alias ExecutionPlane.HTTP, as: ExecutionPlaneHTTP
  alias Pristine.Core.{Context, Request, Response}

  @impl true
  def send(%Request{} = request, %Context{} = context) do
    case normalize_method(request.method) do
      {:ok, method} ->
        request
        |> build_execution_request(method, context)
        |> ExecutionPlaneHTTP.unary(lineage: execution_lineage(request))
        |> normalize_execution_result()

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

  defp build_execution_request(%Request{} = request, method, %Context{} = _context) do
    %{
      url: request.url,
      method: method,
      headers: request.headers,
      body: request.body,
      timeout_ms: Map.get(request.metadata, :timeout)
    }
  end

  defp execution_lineage(%Request{} = request) do
    case idempotency_key(request.headers) do
      nil -> %{}
      key -> %{idempotency_key: key}
    end
  end

  defp normalize_execution_result({:ok, result}) do
    {:ok,
     %Response{
       status: result.outcome.raw_payload.status_code,
       headers: result.outcome.raw_payload.headers,
       body: result.outcome.raw_payload.body
     }}
  end

  defp normalize_execution_result({:error, result}) do
    {:error, {:execution_plane_transport, result.outcome.failure, result.outcome.raw_payload}}
  end

  defp idempotency_key(headers) when is_map(headers) do
    Enum.find_value(headers, fn {key, value} ->
      if String.contains?(String.downcase(to_string(key)), "idempotency-key") do
        to_string(value)
      end
    end)
  end
end
