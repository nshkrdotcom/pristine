defmodule Tinkex.Types.RequestErrorCategory do
  @moduledoc """
  Error category for request failures.

  Mirrors Python tinker.types.request_error_category.RequestErrorCategory.
  Wire format: `"unknown"` | `"server"` | `"user"`

  - `:user` errors are not retryable (e.g., bad request, validation)
  - `:server` errors are retryable (e.g., service unavailable)
  - `:unknown` errors are treated as retryable by default
  """

  @type t :: :unknown | :server | :user

  @doc """
  Parse wire format string to atom (case-insensitive).
  """
  @spec parse(String.t() | nil) :: t()
  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "server" -> :server
      "user" -> :user
      _ -> :unknown
    end
  end

  def parse(_), do: :unknown

  @doc """
  Convert atom to wire format string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(:unknown), do: "unknown"
  def to_string(:server), do: "server"
  def to_string(:user), do: "user"

  @doc """
  Check if errors of this category are retryable.

  User errors are not retryable; server and unknown errors are.
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(:user), do: false
  def retryable?(:server), do: true
  def retryable?(:unknown), do: true
end
