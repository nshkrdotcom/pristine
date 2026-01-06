defmodule Tinkex.Types.RequestFailedResponse do
  @moduledoc """
  Response payload for failed requests.

  Mirrors Python tinker.types.RequestFailedResponse.
  Contains the error message and category for retry logic.
  """

  alias Tinkex.Types.RequestErrorCategory

  @enforce_keys [:error, :category]
  defstruct [:error, :category]

  @type t :: %__MODULE__{
          error: String.t(),
          category: RequestErrorCategory.t()
        }

  @doc """
  Create a new RequestFailedResponse.
  """
  @spec new(String.t(), RequestErrorCategory.t()) :: t()
  def new(error, category) when is_binary(error) do
    %__MODULE__{error: error, category: category}
  end

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"error" => error, "category" => category}) do
    %__MODULE__{
      error: error,
      category: RequestErrorCategory.parse(category)
    }
  end

  def from_json(%{"error" => error} = json) do
    %__MODULE__{
      error: error,
      category: RequestErrorCategory.parse(json["category"])
    }
  end

  def from_json(%{error: error, category: category}) do
    %__MODULE__{
      error: error,
      category: RequestErrorCategory.parse(category)
    }
  end

  def from_json(%{error: error} = json) do
    %__MODULE__{
      error: error,
      category: RequestErrorCategory.parse(json[:category])
    }
  end
end
