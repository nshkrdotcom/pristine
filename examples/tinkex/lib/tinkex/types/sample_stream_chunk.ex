defmodule Tinkex.Types.SampleStreamChunk do
  @moduledoc """
  A chunk from streaming text generation.

  Mirrors Python `tinker.types.SampleStreamChunk`.

  ## Fields

  - `token` - Generated token string
  - `token_id` - Token ID (integer)
  - `index` - Position in sequence
  - `finish_reason` - Why generation stopped (if final chunk)
  - `total_tokens` - Total tokens generated (if final chunk)
  - `logprob` - Log probability of this token
  - `event_type` - Type of event: :token, :done, or :error

  ## Event Types

  - `:token` - Regular token chunk
  - `:done` - Final chunk, generation complete
  - `:error` - Error occurred during streaming
  """

  @derive {Jason.Encoder,
           only: [:token, :token_id, :index, :finish_reason, :total_tokens, :logprob, :event_type]}
  defstruct [
    :token,
    :token_id,
    :index,
    :finish_reason,
    :total_tokens,
    :logprob,
    event_type: :token
  ]

  @type t :: %__MODULE__{
          token: String.t() | nil,
          token_id: integer() | nil,
          index: non_neg_integer() | nil,
          finish_reason: String.t() | nil,
          total_tokens: non_neg_integer() | nil,
          logprob: float() | nil,
          event_type: :token | :done | :error
        }

  @doc """
  Create a chunk from an SSE event map.

  ## Parameters

  - `map` - Map from SSE event data

  ## Examples

      chunk = SampleStreamChunk.from_map(%{
        "token" => "Hello",
        "token_id" => 12345,
        "index" => 0
      })
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      token: map["token"] || map[:token],
      token_id: map["token_id"] || map[:token_id],
      index: map["index"] || map[:index],
      finish_reason: map["finish_reason"] || map[:finish_reason],
      total_tokens: map["total_tokens"] || map[:total_tokens],
      logprob: map["logprob"] || map[:logprob],
      event_type: parse_event_type(map)
    }
  end

  @doc """
  Create a done chunk indicating generation is complete.

  ## Parameters

  - `finish_reason` - Why generation stopped (optional)
  - `total_tokens` - Total tokens generated (optional)

  ## Examples

      chunk = SampleStreamChunk.done("length", 100)
  """
  @spec done(String.t() | nil, non_neg_integer() | nil) :: t()
  def done(finish_reason \\ nil, total_tokens \\ nil) do
    %__MODULE__{
      finish_reason: finish_reason,
      total_tokens: total_tokens,
      event_type: :done
    }
  end

  @doc """
  Create an error chunk.

  ## Parameters

  - `message` - Error message

  ## Examples

      chunk = SampleStreamChunk.error("Connection lost")
  """
  @spec error(String.t()) :: t()
  def error(message) do
    %__MODULE__{
      token: message,
      event_type: :error
    }
  end

  @doc """
  Check if this is a final chunk.

  Returns true if the chunk has event_type :done or has a finish_reason.

  ## Examples

      SampleStreamChunk.done?(%SampleStreamChunk{event_type: :done})
      #=> true

      SampleStreamChunk.done?(%SampleStreamChunk{finish_reason: "length"})
      #=> true

      SampleStreamChunk.done?(%SampleStreamChunk{token: "hello"})
      #=> false
  """
  @spec done?(t()) :: boolean()
  def done?(%__MODULE__{event_type: :done}), do: true
  def done?(%__MODULE__{finish_reason: reason}) when not is_nil(reason), do: true
  def done?(%__MODULE__{}), do: false

  # Parse event type from map
  defp parse_event_type(map) do
    cond do
      map["event_type"] == "done" or map[:event_type] == :done ->
        :done

      map["event_type"] == "error" or map[:event_type] == :error ->
        :error

      not is_nil(map["finish_reason"] || map[:finish_reason]) ->
        :done

      true ->
        :token
    end
  end
end
