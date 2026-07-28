defmodule Pristine.RuntimeGateway.Materialization do
  @moduledoc false

  alias ExecutionPlane.Family.HTTPRequest
  alias ExecutionPlane.Runtime.Error
  alias Pristine.Core.{Context, Request}

  @type mode :: :unary | :incremental
  @type validated :: %{
          family_request: HTTPRequest.t(),
          request: Request.t(),
          context: Context.t(),
          endpoint: URI.t()
        }

  @spec validate(HTTPRequest.t() | map(), keyword(), mode()) ::
          {:ok, validated()} | {:error, Error.t()}
  def validate(family_request, opts, mode)
      when is_list(opts) and mode in [:unary, :incremental] do
    expected_mode = Atom.to_string(mode)

    with {:ok, family_request} <- normalize_family_request(family_request),
         :ok <- require_response_mode(family_request, expected_mode),
         {:ok, request} <- fetch_request(opts),
         {:ok, context} <- fetch_context(opts),
         {:ok, endpoint} <- fetch_endpoint(opts),
         {:ok, request_uri} <- request_uri(request),
         :ok <- validate_endpoint_binding(endpoint, request_uri),
         :ok <- validate_request_binding(family_request, request, request_uri),
         {:ok, request} <- bind_deadline(request, family_request.deadline_at) do
      {:ok,
       %{
         family_request: family_request,
         request: request,
         context: context,
         endpoint: endpoint
       }}
    end
  end

  @spec runtime_payload(validated()) :: map()
  def runtime_payload(%{
        family_request: family_request,
        request: request,
        endpoint: endpoint
      }) do
    %{
      "family" => "http",
      "contract_version" => 1,
      "request" => %{
        "request_ref" => family_request.request_ref,
        "endpoint_ref" => family_request.endpoint_ref,
        "method" => family_request.method,
        "path" => family_request.path,
        "header_policy_ref" => family_request.header_policy_ref,
        "response_mode" => family_request.response_mode,
        "idempotency_key" => family_request.idempotency_key,
        "deadline_at" => DateTime.to_iso8601(family_request.deadline_at),
        "body_artifact_ref" => family_request.body_artifact_ref
      },
      "materialization" => %{
        "method" => normalize_method(request.method),
        "url" => request.url,
        "headers" => stringify_headers(request.headers),
        "body" => request.body,
        "endpoint_id" => request.endpoint_id
      },
      "egress" => %{
        "scheme" => endpoint.scheme,
        "host" => endpoint.host,
        "port" => normalized_port(endpoint)
      }
    }
  end

  defp normalize_family_request(%HTTPRequest{} = request), do: normalize_family_attrs(request)
  defp normalize_family_request(attrs), do: normalize_family_attrs(attrs)

  defp normalize_family_attrs(attrs) do
    case HTTPRequest.new(attrs) do
      {:ok, request} -> {:ok, request}
      {:error, _reason} -> {:error, error("HTTP family request is invalid")}
    end
  end

  defp require_response_mode(%HTTPRequest{response_mode: mode}, mode), do: :ok

  defp require_response_mode(_request, _mode) do
    {:error, error("HTTP response mode does not match the selected gateway operation")}
  end

  defp fetch_request(opts) do
    case Keyword.fetch(opts, :request) do
      {:ok, %Request{} = request} -> {:ok, request}
      _other -> {:error, error("materialized Pristine request is required")}
    end
  end

  defp fetch_context(opts) do
    case Keyword.fetch(opts, :context) do
      {:ok, %Context{} = context} -> {:ok, context}
      _other -> {:error, error("materialized Pristine context is required")}
    end
  end

  defp fetch_endpoint(opts) do
    with {:ok, endpoint} when is_binary(endpoint) <- Keyword.fetch(opts, :endpoint),
         %URI{} = uri <- URI.parse(endpoint),
         true <- valid_endpoint?(uri) do
      {:ok, uri}
    else
      _other -> {:error, error("an explicit HTTP or HTTPS endpoint is required")}
    end
  end

  defp request_uri(%Request{url: url}) when is_binary(url) do
    uri = URI.parse(url)

    if valid_request_uri?(uri) do
      {:ok, uri}
    else
      {:error, error("materialized request URL is not a valid HTTP or HTTPS URL")}
    end
  end

  defp request_uri(_request),
    do: {:error, error("materialized request URL is not a valid HTTP or HTTPS URL")}

  defp valid_endpoint?(%URI{} = uri) do
    valid_http_origin?(uri) and is_nil(uri.userinfo) and is_nil(uri.query) and
      is_nil(uri.fragment)
  end

  defp valid_request_uri?(%URI{} = uri) do
    valid_http_origin?(uri) and is_nil(uri.userinfo)
  end

  defp valid_http_origin?(%URI{scheme: scheme, host: host}) do
    scheme in ["http", "https"] and is_binary(host) and String.trim(host) != ""
  end

  defp validate_endpoint_binding(endpoint, request_uri) do
    cond do
      origin(endpoint) != origin(request_uri) ->
        {:error, error("materialized request violates its explicit egress endpoint")}

      not within_endpoint_path?(endpoint.path, request_uri.path) ->
        {:error, error("materialized request path is outside its explicit egress endpoint")}

      true ->
        :ok
    end
  end

  defp validate_request_binding(family_request, request, request_uri) do
    cond do
      normalize_method(request.method) != family_request.method ->
        {:error, error("materialized request method does not match the HTTP family request")}

      normalize_path(request_uri.path) != family_request.path ->
        {:error, error("materialized request path does not match the HTTP family request")}

      not idempotency_bound?(request.headers, family_request.idempotency_key) ->
        {:error, error("materialized request is missing its bound idempotency key")}

      not body_artifact_bound?(request.body, family_request.body_artifact_ref) ->
        {:error, error("materialized request body is missing its artifact reference")}

      true ->
        :ok
    end
  end

  defp bind_deadline(%Request{} = request, %DateTime{} = deadline) do
    remaining_ms = DateTime.diff(deadline, DateTime.utc_now(), :millisecond)

    if remaining_ms > 0 do
      metadata = request.metadata || %{}
      configured_timeout = Map.get(metadata, :timeout, Map.get(metadata, "timeout"))

      timeout =
        case configured_timeout do
          value when is_integer(value) and value > 0 -> min(value, remaining_ms)
          _other -> remaining_ms
        end

      {:ok, %Request{request | metadata: Map.put(metadata, :timeout, max(timeout, 1))}}
    else
      {:error,
       Error.new!(
         category: "timeout",
         message: "HTTP family request deadline has expired",
         retryable: false,
         ambiguous: false
       )}
    end
  end

  defp bind_deadline(_request, _deadline),
    do: {:error, error("HTTP family request deadline is invalid")}

  defp idempotency_bound?(headers, expected) when is_binary(expected) do
    Enum.any?(headers || %{}, fn {name, value} ->
      normalized_name = name |> to_string() |> String.downcase()
      String.ends_with?(normalized_name, "idempotency-key") and to_string(value) == expected
    end)
  end

  defp idempotency_bound?(_headers, _expected), do: false

  defp body_artifact_bound?(nil, _artifact_ref), do: true
  defp body_artifact_bound?(_body, artifact_ref), do: present_string?(artifact_ref)

  defp origin(uri), do: {uri.scheme, String.downcase(uri.host), normalized_port(uri)}

  defp normalized_port(%URI{port: port}) when is_integer(port), do: port
  defp normalized_port(%URI{scheme: "https"}), do: 443
  defp normalized_port(%URI{scheme: "http"}), do: 80

  defp within_endpoint_path?(nil, _request_path), do: true
  defp within_endpoint_path?("", _request_path), do: true
  defp within_endpoint_path?("/", _request_path), do: true

  defp within_endpoint_path?(endpoint_path, request_path) do
    endpoint_path = String.trim_trailing(endpoint_path, "/")
    request_path = normalize_path(request_path)

    request_path == endpoint_path or String.starts_with?(request_path, endpoint_path <> "/")
  end

  defp normalize_path(nil), do: "/"
  defp normalize_path(""), do: "/"
  defp normalize_path(path), do: path

  defp normalize_method(method) when is_atom(method),
    do: method |> Atom.to_string() |> String.upcase()

  defp normalize_method(method) when is_binary(method), do: String.upcase(method)
  defp normalize_method(method), do: method

  defp stringify_headers(headers) do
    Map.new(headers || %{}, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp error(message) do
    Error.new!(
      category: "invalid_request",
      message: message,
      retryable: false,
      ambiguous: false
    )
  end
end
