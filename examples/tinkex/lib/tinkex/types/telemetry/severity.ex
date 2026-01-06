defmodule Tinkex.Types.Telemetry.Severity do
  @moduledoc """
  Log severity level enum.

  Mirrors Python tinker.types.severity.Severity.
  Wire format: `"DEBUG"` | `"INFO"` | `"WARNING"` | `"ERROR"` | `"CRITICAL"`
  """

  @type t :: :debug | :info | :warning | :error | :critical

  @values [:debug, :info, :warning, :error, :critical]

  @doc """
  Returns all valid severity levels.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Parse wire format string to atom.
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse("DEBUG"), do: :debug
  def parse("INFO"), do: :info
  def parse("WARNING"), do: :warning
  def parse("ERROR"), do: :error
  def parse("CRITICAL"), do: :critical
  def parse(_), do: nil

  @doc """
  Convert atom to wire format string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(:debug), do: "DEBUG"
  def to_string(:info), do: "INFO"
  def to_string(:warning), do: "WARNING"
  def to_string(:error), do: "ERROR"
  def to_string(:critical), do: "CRITICAL"
end
