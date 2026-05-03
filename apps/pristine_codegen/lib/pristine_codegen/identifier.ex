defmodule PristineCodegen.Identifier do
  @moduledoc false

  @spec atom!(atom() | String.t(), String.t()) :: atom()
  def atom!(value, context \\ "identifier")
  def atom!(value, _context) when is_atom(value), do: value

  def atom!(value, context) when is_binary(value) do
    if atom_identifier?(value) do
      :"#{value}"
    else
      raise ArgumentError, "#{context} is not a bounded Elixir identifier: #{inspect(value)}"
    end
  end

  @spec module_segment!(String.t(), String.t()) :: String.t()
  def module_segment!(value, context \\ "module segment") when is_binary(value) do
    if alias_segment?(value) do
      value
    else
      raise ArgumentError, "#{context} is not a bounded module segment: #{inspect(value)}"
    end
  end

  @spec artifact_atom!(String.t()) :: atom()
  def artifact_atom!(relative_path) when is_binary(relative_path) do
    relative_path
    |> Path.rootname()
    |> String.replace("/", "_")
    |> atom!("artifact id")
  end

  defp atom_identifier?(<<first, rest::binary>>) when first in ?a..?z or first == ?_ do
    atom_identifier_tail?(rest)
  end

  defp atom_identifier?(_value), do: false

  defp atom_identifier_tail?(<<>>), do: true

  defp atom_identifier_tail?(<<last>>) when last in [??, ?!], do: true

  defp atom_identifier_tail?(<<char, rest::binary>>) when char in ?a..?z,
    do: atom_identifier_tail?(rest)

  defp atom_identifier_tail?(<<char, rest::binary>>) when char in ?A..?Z,
    do: atom_identifier_tail?(rest)

  defp atom_identifier_tail?(<<char, rest::binary>>) when char in ?0..?9,
    do: atom_identifier_tail?(rest)

  defp atom_identifier_tail?(<<?_, rest::binary>>), do: atom_identifier_tail?(rest)
  defp atom_identifier_tail?(_value), do: false

  defp alias_segment?(<<first, rest::binary>>) when first in ?A..?Z do
    alias_segment_tail?(rest)
  end

  defp alias_segment?(_value), do: false

  defp alias_segment_tail?(<<>>), do: true

  defp alias_segment_tail?(<<char, rest::binary>>) when char in ?a..?z,
    do: alias_segment_tail?(rest)

  defp alias_segment_tail?(<<char, rest::binary>>) when char in ?A..?Z,
    do: alias_segment_tail?(rest)

  defp alias_segment_tail?(<<char, rest::binary>>) when char in ?0..?9,
    do: alias_segment_tail?(rest)

  defp alias_segment_tail?(<<?_, rest::binary>>), do: alias_segment_tail?(rest)
  defp alias_segment_tail?(_value), do: false
end
