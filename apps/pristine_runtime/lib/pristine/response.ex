defmodule Pristine.Response do
  @moduledoc """
  Public runtime response wrapper for execute and stream workflows.
  """

  alias Pristine.Core.{Response, StreamResponse}

  @type t :: %__MODULE__{
          status: integer() | nil,
          headers: map(),
          body: term(),
          stream: Enumerable.t() | nil,
          metadata: map()
        }

  defstruct status: nil,
            headers: %{},
            body: nil,
            stream: nil,
            metadata: %{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    struct(__MODULE__, opts)
  end

  @spec from_transport(Response.t()) :: t()
  def from_transport(%Response{} = response) do
    %__MODULE__{
      status: response.status,
      headers: response.headers,
      body: response.body,
      metadata: response.metadata
    }
  end

  @spec from_stream(StreamResponse.t()) :: t()
  def from_stream(%StreamResponse{} = response) do
    %__MODULE__{
      status: response.status,
      headers: response.headers,
      stream: response.stream,
      metadata: response.metadata
    }
  end
end
