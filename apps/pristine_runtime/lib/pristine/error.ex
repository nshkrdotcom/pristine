defmodule Pristine.Error do
  @moduledoc """
  Structured error types for API responses.

  This module provides a unified error representation for all types
  of errors that can occur during API requests, including:

  - HTTP response errors (4xx, 5xx)
  - Connection errors
  - Timeout errors

  ## Error Types

  | Type | Description |
  |------|-------------|
  | `:bad_request` | 400 - Bad request |
  | `:authentication` | 401 - Authentication failed |
  | `:permission_denied` | 403 - Permission denied |
  | `:not_found` | 404 - Resource not found |
  | `:conflict` | 409 - Conflict/lock timeout |
  | `:unprocessable_entity` | 422 - Validation failed |
  | `:rate_limit` | 429 - Too many requests |
  | `:internal_server` | 5xx - Server error |
  | `:timeout` | Request timed out |
  | `:connection` | Connection failed |
  | `:unknown` | Unknown error type |

  ## Example

      case make_request() do
        {:ok, response} ->
          {:ok, response}

        {:error, %Pristine.Error{type: :rate_limit} = error} ->
          Logger.warning("Rate limited: \#{Error.message(error)}")
          {:retry, error}

        {:error, %Pristine.Error{type: :authentication}} ->
          {:error, :invalid_credentials}

        {:error, error} ->
          {:error, Error.message(error)}
      end
  """

  alias Pristine.Core.Response
  alias Pristine.Response, as: PublicResponse
  alias Pristine.SDK.ProviderProfile

  @type error_type ::
          :bad_request
          | :authentication
          | :permission_denied
          | :not_found
          | :conflict
          | :unprocessable_entity
          | :rate_limit
          | :internal_server
          | :timeout
          | :connection
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          status: integer() | nil,
          message: String.t() | nil,
          body: term(),
          response: Response.t() | nil,
          provider: atom() | String.t() | nil,
          provider_code: atom() | nil,
          headers: map(),
          request_id: String.t() | nil,
          retry_after_ms: non_neg_integer() | nil,
          documentation_url: String.t() | nil,
          additional_data: term()
        }

  @retriable_types [:rate_limit, :internal_server, :timeout, :connection]

  defexception [
    :type,
    :status,
    :message,
    :body,
    :response,
    :provider,
    :provider_code,
    :headers,
    :request_id,
    :retry_after_ms,
    :documentation_url,
    :additional_data
  ]

  @doc """
  Create an error from an HTTP response.

  Maps the HTTP status code to an error type and preserves
  the response body and headers for inspection.

  ## Examples

      iex> response = %Response{status: 429, body: "Too many requests"}
      iex> error = Error.from_response(response)
      iex> error.type
      :rate_limit
  """
  @spec from_response(PublicResponse.t() | Response.t()) :: t()
  def from_response(%PublicResponse{} = response) do
    %Response{
      status: response.status,
      headers: response.headers,
      body: response.body,
      metadata: response.metadata
    }
    |> from_response()
  end

  def from_response(%Response{} = response) do
    from_response(response, body: response.body)
  end

  def from_response(%PublicResponse{} = response, opts) when is_list(opts) do
    %Response{
      status: response.status,
      headers: response.headers,
      body: response.body,
      metadata: response.metadata
    }
    |> from_response(opts)
  end

  @spec from_response(Response.t(), keyword()) :: t()
  def from_response(%Response{status: status} = response, opts) when is_list(opts) do
    body = Keyword.get(opts, :body, response.body)
    profile = Keyword.get(opts, :profile)
    normalized_headers = ProviderProfile.normalize_headers(response.headers)
    normalized_body = ProviderProfile.normalize_body(body)

    rate_limited? =
      ProviderProfile.rate_limited?(profile, status, normalized_headers, normalized_body)

    retry_after_ms =
      Keyword.get(opts, :retry_after_ms) ||
        ProviderProfile.retry_after_ms(profile, normalized_headers)

    normalized_response = %Response{response | body: normalized_body, headers: normalized_headers}

    %__MODULE__{
      type: error_type(status, rate_limited?),
      status: status,
      message: ProviderProfile.message(profile, normalized_body) || status_to_message(status),
      body: normalized_body,
      response: normalized_response,
      provider: provider(profile),
      provider_code:
        ProviderProfile.provider_code(profile, status, normalized_body, rate_limited?),
      headers: normalized_headers,
      request_id: ProviderProfile.request_id(profile, normalized_body, normalized_headers),
      retry_after_ms: retry_after_ms,
      documentation_url: ProviderProfile.documentation_url(profile, normalized_body),
      additional_data: ProviderProfile.additional_data(profile, normalized_body)
    }
  end

  @doc """
  Create a connection error.

  ## Examples

      iex> error = Error.connection_error(:econnrefused)
      iex> error.type
      :connection
  """
  @spec connection_error(term()) :: t()
  def connection_error(reason) do
    connection_error(reason, [])
  end

  @spec connection_error(term(), keyword()) :: t()
  def connection_error(reason, opts) when is_list(opts) do
    profile = Keyword.get(opts, :profile)

    %__MODULE__{
      type: :connection,
      message: "Connection failed: #{inspect(reason)}",
      body: %{reason: inspect(reason)},
      provider: provider(profile),
      provider_code: ProviderProfile.connection_code(profile),
      headers: %{}
    }
  end

  @doc """
  Create a timeout error.

  ## Examples

      iex> error = Error.timeout_error()
      iex> error.type
      :timeout
  """
  @spec timeout_error() :: t()
  def timeout_error do
    %__MODULE__{
      type: :timeout,
      message: "Request timed out",
      headers: %{}
    }
  end

  @doc """
  Create a validation error.
  """
  @spec validation_error(term(), term(), keyword()) :: t()
  def validation_error(reason, body, opts \\ []) do
    profile = Keyword.get(opts, :profile)

    %__MODULE__{
      type: :bad_request,
      message: "Validation error: #{inspect(reason)}",
      body: body,
      provider: provider(profile),
      provider_code: ProviderProfile.validation_code(profile),
      headers: %{}
    }
  end

  @doc """
  Get a human-readable error message.

  Returns the custom message if set, otherwise returns
  a default message based on the error type.

  This function is also the Exception callback for `Exception.message/1`.

  ## Examples

      iex> Error.message(%Error{message: "Custom message"})
      "Custom message"

      iex> Error.message(%Error{type: :rate_limit})
      "Rate limit exceeded"
  """
  @impl true
  @spec message(t()) :: String.t()
  def message(%__MODULE__{message: msg}) when is_binary(msg), do: msg
  def message(%__MODULE__{type: type}), do: type_to_message(type)

  @doc """
  Determine if an error is retriable.

  Checks both the error type and any `x-should-retry` header
  in the response (if present).

  ## Retriable Types

  - `:rate_limit` - 429 errors (usually with Retry-After)
  - `:internal_server` - 5xx errors
  - `:timeout` - Request timeouts
  - `:connection` - Connection failures

  ## Examples

      iex> Error.retriable?(%Error{type: :rate_limit})
      true

      iex> Error.retriable?(%Error{type: :not_found})
      false
  """
  @spec retriable?(t()) :: boolean()
  def retriable?(%__MODULE__{response: %Response{headers: headers}} = error)
      when is_map(headers) do
    headers = normalize_header_keys(headers)

    case headers["x-should-retry"] do
      "true" -> true
      "false" -> false
      _ -> type_retriable?(error.type)
    end
  end

  def retriable?(%__MODULE__{type: type}), do: type_retriable?(type)

  # Private functions

  defp normalize_header_keys(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)
  end

  defp type_retriable?(type) when type in @retriable_types, do: true
  defp type_retriable?(_type), do: false

  defp error_type(_status, true), do: :rate_limit
  defp error_type(status, false), do: status_to_type(status)

  defp status_to_type(400), do: :bad_request
  defp status_to_type(401), do: :authentication
  defp status_to_type(403), do: :permission_denied
  defp status_to_type(404), do: :not_found
  defp status_to_type(409), do: :conflict
  defp status_to_type(422), do: :unprocessable_entity
  defp status_to_type(429), do: :rate_limit
  defp status_to_type(status) when status >= 500 and status < 600, do: :internal_server
  defp status_to_type(_), do: :unknown

  defp status_to_message(400), do: "Bad request"
  defp status_to_message(401), do: "Authentication failed"
  defp status_to_message(403), do: "Permission denied"
  defp status_to_message(404), do: "Resource not found"
  defp status_to_message(409), do: "Conflict"
  defp status_to_message(422), do: "Unprocessable entity"
  defp status_to_message(429), do: "Rate limit exceeded"
  defp status_to_message(status) when status >= 500 and status < 600, do: "Internal server error"
  defp status_to_message(_), do: "Unknown error"

  defp type_to_message(:bad_request), do: "Bad request"
  defp type_to_message(:authentication), do: "Authentication failed"
  defp type_to_message(:permission_denied), do: "Permission denied"
  defp type_to_message(:not_found), do: "Resource not found"
  defp type_to_message(:conflict), do: "Conflict"
  defp type_to_message(:unprocessable_entity), do: "Unprocessable entity"
  defp type_to_message(:rate_limit), do: "Rate limit exceeded"
  defp type_to_message(:internal_server), do: "Internal server error"
  defp type_to_message(:timeout), do: "Request timed out"
  defp type_to_message(:connection), do: "Connection failed"
  defp type_to_message(_), do: "Unknown error"

  defp provider(%ProviderProfile{provider: provider}), do: provider
  defp provider(_profile), do: nil
end
