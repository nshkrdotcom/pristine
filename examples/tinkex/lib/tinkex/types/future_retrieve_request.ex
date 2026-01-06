defmodule Tinkex.Types.FutureRetrieveRequest do
  @moduledoc """
  Request to retrieve the status/result of an async operation.
  """

  @enforce_keys [:request_id]
  defstruct [:request_id]

  @type t :: %__MODULE__{
          request_id: String.t()
        }

  @spec new(String.t()) :: t()
  def new(request_id) when is_binary(request_id) do
    %__MODULE__{request_id: request_id}
  end

  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{request_id: request_id}) do
    %{"request_id" => request_id}
  end

  @spec from_json(map()) :: t()
  def from_json(%{"request_id" => request_id}), do: new(request_id)
  def from_json(%{request_id: request_id}), do: new(request_id)
end
