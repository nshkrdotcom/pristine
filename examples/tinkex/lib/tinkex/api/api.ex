defmodule Tinkex.API do
  @moduledoc """
  High-level HTTP API client for Tinkex.

  Centralizes retry logic, telemetry, pool routing, and error categorization.
  Every function requires an explicit `Tinkex.Config` via `opts[:config]`.

  ## Client Resolution

  The `client_module/1` function determines which HTTP client implementation to use:

  1. If `opts[:http_client]` is set, use that module
  2. If `config.http_client` is set, use that module
  3. Otherwise, use `Tinkex.API` (default implementation)

  This allows tests to inject mock clients without changing the API modules.
  """

  @behaviour Tinkex.HTTPClient

  alias Tinkex.Error

  @doc """
  Resolve the HTTP client module for a request based on options/config.

  ## Examples

      # Use default client
      client = Tinkex.API.client_module(config: config)
      client.post("/api/v1/endpoint", body, opts)

      # Use custom client for testing
      client = Tinkex.API.client_module(http_client: MockClient, config: config)
  """
  @spec client_module(keyword()) :: module()
  def client_module(opts) do
    cond do
      is_atom(opts[:http_client]) and not is_nil(opts[:http_client]) ->
        opts[:http_client]

      match?(
        %Tinkex.Config{http_client: client} when is_atom(client) and not is_nil(client),
        Keyword.get(opts, :config)
      ) ->
        Keyword.fetch!(opts, :config).http_client

      true ->
        __MODULE__
    end
  end

  @impl true
  @spec post(String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(_path, _body, _opts) do
    {:error, Error.new(:api_connection, "HTTP client not implemented - use a custom http_client")}
  end

  @impl true
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(_path, _opts) do
    {:error, Error.new(:api_connection, "HTTP client not implemented - use a custom http_client")}
  end

  @impl true
  @spec delete(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def delete(_path, _opts) do
    {:error, Error.new(:api_connection, "HTTP client not implemented - use a custom http_client")}
  end
end
