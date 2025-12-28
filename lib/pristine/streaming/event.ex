defmodule Pristine.Streaming.Event do
  @moduledoc """
  Represents a Server-Sent Event (SSE).

  ## Fields

    * `:event` - Event type (optional, defaults to "message" per SSE spec)
    * `:data` - Event data as string
    * `:id` - Event ID for reconnection (optional)
    * `:retry` - Retry interval in milliseconds (optional)

  ## Example

      %Event{
        event: "update",
        data: ~s({"status": "complete"}),
        id: "evt_123"
      }

  ## JSON Parsing

  Use `json/1` to safely parse the data field:

      case Event.json(event) do
        {:ok, data} -> handle_data(data)
        {:error, reason} -> handle_error(reason)
      end

  Or use `json!/1` when you expect valid JSON:

      data = Event.json!(event)
  """

  @type t :: %__MODULE__{
          event: String.t() | nil,
          data: String.t() | nil,
          id: String.t() | nil,
          retry: non_neg_integer() | nil
        }

  defstruct [:event, :data, :id, :retry]

  @doc """
  Parse the event's data field as JSON.

  Returns `{:ok, term()}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> event = %Pristine.Streaming.Event{data: ~s({"key": "value"})}
      iex> {:ok, data} = Pristine.Streaming.Event.json(event)
      iex> data["key"]
      "value"

      iex> event = %Pristine.Streaming.Event{data: nil}
      iex> Pristine.Streaming.Event.json(event)
      {:error, :no_data}
  """
  @spec json(t()) :: {:ok, term()} | {:error, term()}
  def json(%__MODULE__{data: nil}), do: {:error, :no_data}
  def json(%__MODULE__{data: ""}), do: {:error, :empty_data}

  def json(%__MODULE__{data: data}) when is_binary(data) do
    Jason.decode(data)
  end

  @doc """
  Parse the event's data field as JSON, raising on error.

  ## Examples

      iex> event = %Pristine.Streaming.Event{data: ~s({"key": "value"})}
      iex> Pristine.Streaming.Event.json!(event)
      %{"key" => "value"}

  Raises `Jason.DecodeError` for invalid JSON, or `ArgumentError` for nil/empty data.
  """
  @spec json!(t()) :: term()
  def json!(%__MODULE__{data: nil}) do
    raise ArgumentError, "cannot parse JSON from nil data"
  end

  def json!(%__MODULE__{data: ""}) do
    raise ArgumentError, "cannot parse JSON from empty data"
  end

  def json!(%__MODULE__{data: data}) when is_binary(data) do
    Jason.decode!(data)
  end

  @doc """
  Check if this is a message event.

  Per the SSE specification, events without an explicit event type
  default to "message".

  ## Examples

      iex> event = %Pristine.Streaming.Event{data: "test"}
      iex> Pristine.Streaming.Event.message?(event)
      true

      iex> event = %Pristine.Streaming.Event{event: "error", data: "test"}
      iex> Pristine.Streaming.Event.message?(event)
      false
  """
  @spec message?(t()) :: boolean()
  def message?(%__MODULE__{event: nil}), do: true
  def message?(%__MODULE__{event: "message"}), do: true
  def message?(%__MODULE__{}), do: false
end
