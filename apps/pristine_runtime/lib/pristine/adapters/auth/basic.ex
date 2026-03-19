defmodule Pristine.Adapters.Auth.Basic do
  @moduledoc """
  Basic auth adapter.
  """

  @behaviour Pristine.Ports.Auth

  @doc """
  Build a basic auth tuple for Context auth configuration.
  """
  @spec new(String.t(), String.t(), keyword()) :: {module(), keyword()}
  def new(username, password, opts \\ []) when is_list(opts) do
    {__MODULE__, opts |> Keyword.put(:username, username) |> Keyword.put(:password, password)}
  end

  @impl true
  def headers(opts) do
    with {:ok, username} <- fetch_required(opts, :username, :missing_basic_username),
         {:ok, password} <- fetch_required(opts, :password, :missing_basic_password) do
      credentials = Base.encode64("#{username}:#{password}")
      {:ok, %{"Authorization" => "Basic #{credentials}"}}
    end
  end

  defp fetch_required(opts, key, error) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, error}
    end
  end
end
