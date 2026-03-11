defmodule Pristine.Adapters.Serializer.JSON do
  @moduledoc """
  JSON serializer using Jason with optional Sinter validation.
  """

  @behaviour Pristine.Ports.Serializer

  alias Sinter.{Schema, Types, Validator}

  @impl true
  def encode(payload, opts \\ []) do
    with {:ok, validated} <- maybe_validate(payload, Keyword.get(opts, :schema), opts) do
      Jason.encode(validated)
    end
  end

  @impl true
  def decode(payload, schema, opts \\ [])

  def decode(payload, nil, _opts) do
    Jason.decode(payload)
  end

  def decode(payload, schema, opts) do
    with {:ok, decoded} <- Jason.decode(payload) do
      validate(decoded, schema, opts)
    end
  end

  defp validate(decoded, %Schema{} = schema, opts) do
    Validator.validate(schema, decoded, opts)
  end

  defp validate(decoded, type_spec, opts) do
    path = normalize_validation_path(Keyword.get(opts, :path, []))
    coerce = Keyword.get(opts, :coerce, false)

    if coerce do
      with {:ok, coerced} <- Types.coerce(type_spec, decoded) do
        Types.validate(type_spec, coerced, path)
      end
    else
      Types.validate(type_spec, decoded, path)
    end
  end

  defp maybe_validate(payload, nil, _opts), do: {:ok, payload}

  defp maybe_validate(payload, schema, opts) do
    validate(payload, schema, opts)
  end

  defp normalize_validation_path(path) when is_list(path), do: path
  defp normalize_validation_path(_path), do: []
end
