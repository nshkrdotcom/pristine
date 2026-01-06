defmodule Tinkex.NotGiven do
  @moduledoc """
  Sentinel values for distinguishing omitted fields from explicit `nil`.

  Mirrors Python's `NotGiven`/`Omit` pattern so request payload builders can
  drop fields that callers intentionally left out while preserving `nil` values.

  ## Examples

      # Check if a field was omitted
      if NotGiven.not_given?(opts[:temperature]) do
        # Field was not provided, use default
      end

      # Replace sentinel with default
      temperature = NotGiven.coalesce(opts[:temperature], 1.0)

      # Use guards in pattern matching
      def process(value) when is_not_given(value), do: :default
      def process(value), do: value
  """

  @not_given :__tinkex_not_given__
  @omit :__tinkex_omit__

  @doc """
  Retrieve the NotGiven sentinel.

  Use this value to explicitly indicate a field was not provided.
  """
  @spec value() :: atom()
  def value, do: @not_given

  @doc """
  Retrieve the omit sentinel used to explicitly drop default values.

  Different from `value/0` - use this when you want to actively remove
  a field that would otherwise have a default value.
  """
  @spec omit() :: atom()
  def omit, do: @omit

  @doc """
  Check if a value is the NotGiven sentinel.

  Returns `true` if the value is the NotGiven sentinel, `false` otherwise.
  """
  @spec not_given?(term()) :: boolean()
  def not_given?(value), do: value === @not_given

  @doc """
  Guard for checking if a value is the NotGiven sentinel.

  Can be used in function heads and guard clauses.
  """
  defguard is_not_given(value) when value === @not_given

  @doc """
  Check if a value is the omit sentinel.

  Returns `true` if the value is the omit sentinel, `false` otherwise.
  """
  @spec omit?(term()) :: boolean()
  def omit?(value), do: value === @omit

  @doc """
  Guard for checking if a value is the omit sentinel.

  Can be used in function heads and guard clauses.
  """
  defguard is_omit(value) when value === @omit

  @doc """
  Replace sentinel values with the provided fallback.

  If the value is either `NotGiven` or `omit` sentinel, returns the default.
  Otherwise returns the original value unchanged.

  ## Examples

      iex> NotGiven.coalesce(NotGiven.value(), "default")
      "default"

      iex> NotGiven.coalesce("actual", "default")
      "actual"

      iex> NotGiven.coalesce(nil, "default")
      nil
  """
  @spec coalesce(term(), term()) :: term()
  def coalesce(value, default \\ nil) do
    if not_given?(value) or omit?(value) do
      default
    else
      value
    end
  end
end
