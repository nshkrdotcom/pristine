defmodule Pristine.Adapters.Serializer.JSON do
  @moduledoc """
  JSON serializer using Jason with optional Sinter validation.
  """

  @behaviour Pristine.Ports.Serializer

  alias Sinter.Validator

  @impl true
  def encode(payload, _opts \\ []) do
    Jason.encode(payload)
  end

  @impl true
  def decode(payload, schema, opts \\ [])

  def decode(payload, nil, _opts) do
    Jason.decode(payload)
  end

  def decode(payload, schema, opts) do
    with {:ok, decoded} <- Jason.decode(payload) do
      Validator.validate(schema, decoded, opts)
    end
  end
end
