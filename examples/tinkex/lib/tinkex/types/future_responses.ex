defmodule Tinkex.Types.FuturePendingResponse do
  @moduledoc """
  Response indicating a future is still pending.
  """

  defstruct status: "pending"

  @type t :: %__MODULE__{
          status: String.t()
        }
end

defmodule Tinkex.Types.FutureCompletedResponse do
  @moduledoc """
  Response indicating a future has completed successfully.
  """

  @enforce_keys [:status, :result]
  defstruct [:status, :result]

  @type t :: %__MODULE__{
          status: String.t(),
          result: map()
        }
end

defmodule Tinkex.Types.FutureFailedResponse do
  @moduledoc """
  Response indicating a future has failed.
  """

  @enforce_keys [:status, :error]
  defstruct [:status, :error]

  @type t :: %__MODULE__{
          status: String.t(),
          error: map()
        }
end

defmodule Tinkex.Types.FutureRetrieveResponse do
  @moduledoc """
  Union type for future retrieval responses.

  Parses the response based on status field and returns the appropriate type.
  """

  alias Tinkex.Types.{FuturePendingResponse, FutureCompletedResponse, FutureFailedResponse}

  @type t :: FuturePendingResponse.t() | FutureCompletedResponse.t() | FutureFailedResponse.t()

  @doc """
  Parse a future retrieve response from JSON.

  Returns the appropriate response type based on the status field.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"status" => "pending"}) do
    %FuturePendingResponse{}
  end

  def from_json(%{"status" => "completed", "result" => result}) do
    %FutureCompletedResponse{status: "completed", result: result}
  end

  def from_json(%{"status" => "failed", "error" => error}) do
    %FutureFailedResponse{status: "failed", error: error}
  end

  def from_json(%{status: "pending"}) do
    %FuturePendingResponse{}
  end

  def from_json(%{status: "completed", result: result}) do
    %FutureCompletedResponse{status: "completed", result: result}
  end

  def from_json(%{status: "failed", error: error}) do
    %FutureFailedResponse{status: "failed", error: error}
  end
end
