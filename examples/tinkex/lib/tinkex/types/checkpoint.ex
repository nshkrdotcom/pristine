defmodule Tinkex.Types.Checkpoint do
  @moduledoc """
  Checkpoint metadata from the API.

  Contains information about a saved model checkpoint including
  its path, type, size, and creation time.
  """

  alias Tinkex.Types.ParsedCheckpointTinkerPath

  defstruct [
    :checkpoint_id,
    :checkpoint_type,
    :tinker_path,
    :training_run_id,
    :size_bytes,
    :public,
    :time
  ]

  @type t :: %__MODULE__{
          checkpoint_id: String.t(),
          checkpoint_type: String.t(),
          tinker_path: String.t(),
          training_run_id: String.t() | nil,
          size_bytes: integer() | nil,
          public: boolean(),
          time: DateTime.t() | String.t() | nil
        }

  @doc """
  Parse a Checkpoint from a map with string or atom keys.

  Derives training_run_id from tinker_path if not explicitly provided.
  Parses ISO-8601 timestamps into DateTime structs.
  """
  @spec from_map(map()) :: t()
  def from_map(%{} = map) do
    tinker_path = get_field(map, :tinker_path)
    training_run_id = get_field(map, :training_run_id) || training_run_from_path(tinker_path)

    %__MODULE__{
      checkpoint_id: get_field(map, :checkpoint_id),
      checkpoint_type: get_field(map, :checkpoint_type),
      tinker_path: tinker_path,
      training_run_id: training_run_id,
      size_bytes: get_field(map, :size_bytes),
      public: get_field(map, :public) || false,
      time: parse_time(get_field(map, :time))
    }
  end

  @doc """
  Extract training_run_id from a tinker path.
  """
  @spec training_run_from_path(String.t() | nil) :: String.t() | nil
  def training_run_from_path(nil), do: nil

  def training_run_from_path(path) do
    case ParsedCheckpointTinkerPath.from_tinker_path(path) do
      {:ok, parsed} -> parsed.training_run_id
      {:error, _} -> nil
    end
  end

  defp get_field(map, key) do
    Map.get(map, to_string(key)) || Map.get(map, key)
  end

  defp parse_time(nil), do: nil
  defp parse_time(%DateTime{} = dt), do: dt

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> value
    end
  end

  defp parse_time(value), do: value
end
