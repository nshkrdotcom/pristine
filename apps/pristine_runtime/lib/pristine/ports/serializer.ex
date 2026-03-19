defmodule Pristine.Ports.Serializer do
  @moduledoc """
  Serialization boundary for request/response payloads.
  """

  @callback encode(term(), keyword()) :: {:ok, binary()} | {:error, term()}
  @callback decode(binary(), term() | nil, keyword()) :: {:ok, term()} | {:error, term()}
end
