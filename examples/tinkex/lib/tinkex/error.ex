defmodule Tinkex.Error do
  @moduledoc """
  Comprehensive error type for Tinkex API operations.

  Mirrors Python tinker error handling with categorization for retry logic.

  ## Error Types

  - `:api_connection` - Network/connection errors
  - `:api_timeout` - Request timeout errors
  - `:api_status` - HTTP status code errors
  - `:request_failed` - Server-side request failures
  - `:validation` - Input validation errors

  ## Retry Logic

  User errors (4xx status codes, except 408/410/429) are not retryable.
  Server errors (5xx) and unknown errors are retryable.
  """

  alias Tinkex.Types.RequestErrorCategory

  defstruct [:message, :type, :status, :category, :data, :retry_after_ms]

  @type error_type ::
          :api_connection
          | :api_timeout
          | :api_status
          | :request_failed
          | :validation

  @type t :: %__MODULE__{
          message: String.t(),
          type: error_type(),
          status: integer() | nil,
          category: RequestErrorCategory.t() | nil,
          data: map() | nil,
          retry_after_ms: non_neg_integer() | nil
        }

  @doc """
  Create a new error with the given type and message.

  ## Options

  - `:status` - HTTP status code
  - `:category` - Error category for retry logic
  - `:data` - Additional error data
  - `:retry_after_ms` - Suggested retry delay for rate limiting
  """
  @spec new(error_type(), String.t(), keyword()) :: t()
  def new(type, message, opts \\ []) do
    %__MODULE__{
      type: type,
      message: message,
      status: Keyword.get(opts, :status),
      category: Keyword.get(opts, :category),
      data: Keyword.get(opts, :data),
      retry_after_ms: Keyword.get(opts, :retry_after_ms)
    }
  end

  @doc """
  Create an error from an HTTP response status and body.
  """
  @spec from_response(integer(), map()) :: t()
  def from_response(status, body) when is_map(body) do
    message =
      body["error"] || body[:error] || body["message"] || body[:message] || "Unknown error"

    category_str = body["category"] || body[:category]

    %__MODULE__{
      type: :api_status,
      message: message,
      status: status,
      category: if(category_str, do: RequestErrorCategory.parse(category_str), else: nil),
      data: body,
      retry_after_ms: body["retry_after_ms"] || body[:retry_after_ms]
    }
  end

  @doc """
  Check if the error is a user error (not retryable).

  Returns true if:
  - Category is `:user`
  - Status is 4xx (except 408 Request Timeout, 410 Gone, 429 Too Many Requests)
  """
  @spec user_error?(t()) :: boolean()
  def user_error?(%__MODULE__{category: :user}), do: true

  def user_error?(%__MODULE__{status: status}) when is_integer(status) do
    # 4xx errors are user errors, except for some retriable ones
    status >= 400 and status < 500 and status not in [408, 410, 429]
  end

  def user_error?(_), do: false

  @doc """
  Check if the error is retryable.

  User errors are not retryable; other errors are.
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(error), do: not user_error?(error)

  @doc """
  Format the error as a human-readable string.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{type: type, status: nil, message: message}) do
    "[#{type}] #{message}"
  end

  def format(%__MODULE__{type: type, status: status, message: message}) do
    "[#{type} (#{status})] #{message}"
  end
end

defimpl String.Chars, for: Tinkex.Error do
  def to_string(error), do: Tinkex.Error.format(error)
end
