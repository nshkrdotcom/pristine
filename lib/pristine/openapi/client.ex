defmodule Pristine.OpenAPI.Client do
  @moduledoc """
  Internal request contracts for OpenAPI-generated SDK surfaces.

  Provider SDKs should depend on `Pristine.SDK.OpenAPI.Client`.
  """

  @type response_type :: term()

  @type request_t :: %{
          required(:args) => map(),
          required(:call) => {module(), atom()},
          required(:method) => atom(),
          required(:opts) => keyword(),
          required(:path_template) => String.t(),
          required(:path_params) => map(),
          required(:query) => map(),
          required(:body) => term(),
          required(:form_data) => term(),
          optional(:auth) => term(),
          optional(:headers) => map(),
          optional(:security) => [map()] | nil,
          optional(:request) => [{String.t(), response_type()}],
          optional(:response) => [{integer() | :default, response_type()}]
        }

  @type request_spec_t :: %{
          required(:method) => atom() | String.t(),
          required(:path) => String.t(),
          required(:path_params) => map(),
          required(:query) => map(),
          required(:body) => term() | nil,
          required(:form_data) => term() | nil,
          required(:headers) => map() | nil,
          required(:auth) => term() | nil,
          required(:security) => [map()] | nil,
          required(:request_schema) => term() | nil,
          required(:response_schema) => term() | nil,
          required(:id) => String.t() | nil,
          optional(:circuit_breaker) => String.t() | nil,
          optional(:rate_limit) => String.t() | nil,
          optional(:resource) => String.t() | nil,
          optional(:retry) => String.t() | nil,
          optional(:telemetry) => String.t() | nil,
          optional(:timeout) => pos_integer() | nil
        }

  @spec request(request_t()) :: {:ok, request_t()}
  def request(request) when is_map(request), do: {:ok, request}

  @doc """
  Normalize a generated OpenAPI request map into the generic execute-request
  shape accepted by `Pristine.execute_request/3`.
  """
  @spec to_request_spec(request_t()) :: request_spec_t()
  def to_request_spec(%{path_template: path_template} = request) when is_binary(path_template) do
    request
    |> then(fn request ->
      %{
        method: Map.get(request, :method),
        path: path_template,
        path_params: normalize_map(Map.get(request, :path_params)),
        query: normalize_map(Map.get(request, :query)),
        body: request_body(request),
        form_data: request_form_data(request),
        headers: Map.get(request, :headers),
        auth: Map.get(request, :auth),
        security: Map.get(request, :security),
        request_schema: request_schema(request),
        response_schema: response_schema(request),
        id: request_id(request)
      }
    end)
    |> forward_optional_fields(request, [
      :circuit_breaker,
      :rate_limit,
      :resource,
      :retry,
      :telemetry,
      :timeout
    ])
  end

  def to_request_spec(request) do
    raise KeyError, key: :path_template, term: request
  end

  @doc false
  @spec request_schema(request_t()) :: term() | nil
  def request_schema(request) when is_map(request) do
    request
    |> Map.get(:request, [])
    |> json_schema()
  end

  @doc false
  @spec response_schema(request_t()) :: term() | nil
  def response_schema(request) when is_map(request) do
    request
    |> Map.get(:response, [])
    |> Enum.filter(fn
      {status, _schema} when is_integer(status) -> status >= 200 and status < 300
      _other -> false
    end)
    |> Enum.map(&elem(&1, 1))
    |> case do
      [] -> nil
      [schema] -> schema
      schemas -> {:union, schemas}
    end
  end

  @doc false
  @spec request_id(request_t()) :: String.t() | nil
  def request_id(%{call: {module, function}})
      when is_atom(module) and is_atom(function) do
    module
    |> Module.split()
    |> Enum.join(".")
    |> Kernel.<>(".")
    |> Kernel.<>(Atom.to_string(function))
  end

  def request_id(_request), do: nil

  defp request_body(request) do
    body = Map.get(request, :body)

    cond do
      body == %{} and not json_request?(request) -> nil
      body == %{} and Map.get(request, :method) in [:delete, :get, :head] -> nil
      true -> body
    end
  end

  defp request_form_data(request) do
    case Map.get(request, :form_data) do
      form_data when form_data == %{} -> nil
      form_data -> form_data
    end
  end

  defp json_request?(request) do
    request
    |> Map.get(:request, [])
    |> Enum.any?(fn
      {"application/json", _schema} -> true
      _other -> false
    end)
  end

  defp json_schema(entries) do
    Enum.find_value(entries, fn
      {"application/json", schema} -> schema
      {_content_type, _schema} -> nil
    end)
  end

  defp normalize_map(nil), do: %{}

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_map(map) when is_list(map) do
    if Keyword.keyword?(map) do
      Map.new(map, fn {key, value} -> {to_string(key), value} end)
    else
      %{}
    end
  end

  defp normalize_map(_map), do: %{}

  defp forward_optional_fields(spec, request, fields) do
    Enum.reduce(fields, spec, fn field, acc ->
      if Map.has_key?(request, field) do
        Map.put(acc, field, Map.get(request, field))
      else
        acc
      end
    end)
  end
end
