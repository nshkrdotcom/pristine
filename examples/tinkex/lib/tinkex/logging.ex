defmodule Tinkex.Logging do
  @moduledoc """
  Logger configuration helper for Tinkex.

  Provides centralized log level configuration with support for:
  - Per-process log isolation (for test harness compatibility)
  - Global log level configuration
  - Level normalization (:warn -> :warning for Logger compatibility)
  """

  require Logger

  @doc """
  Set the log level if provided.

  - If `nil`, does nothing
  - If the process is isolated (test mode), sets process-level logging
  - Otherwise, configures the global Logger level
  """
  @spec maybe_set_level(Logger.level() | nil) :: :ok
  def maybe_set_level(nil), do: :ok

  def maybe_set_level(level) when level in [:debug, :info, :warn, :warning, :error] do
    normalized = normalize_level(level)

    cond do
      # Check for test harness process isolation
      Process.get(:logger_isolated) ->
        Logger.put_process_level(self(), normalized)

      # Already at the desired level
      Logger.level() == normalized ->
        :ok

      # Configure globally
      true ->
        Logger.configure(level: normalized)
    end
  end

  @doc """
  Normalize log level to Logger-compatible format.

  Converts `:warn` to `:warning` for Logger 1.15+ compatibility.
  """
  @spec normalize_level(atom()) :: Logger.level()
  def normalize_level(:warn), do: :warning
  def normalize_level(level), do: level
end
