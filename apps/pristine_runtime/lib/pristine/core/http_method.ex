defmodule Pristine.Core.HTTPMethod do
  @moduledoc false

  @known_methods %{
    "delete" => :delete,
    "get" => :get,
    "head" => :head,
    "options" => :options,
    "patch" => :patch,
    "post" => :post,
    "put" => :put,
    "trace" => :trace
  }

  @spec telemetry(atom() | String.t() | term()) :: atom() | String.t() | term()
  def telemetry(method) when is_atom(method), do: method

  def telemetry(method) when is_binary(method) do
    normalized = String.downcase(method)
    Map.get(@known_methods, normalized, normalized)
  end

  def telemetry(method), do: method
end
