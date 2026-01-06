defmodule Tinkex.Types.CheckpointsListResponse do
  @moduledoc """
  Response containing a list of checkpoints with pagination cursor.
  """

  alias Tinkex.Types.{Checkpoint, Cursor}

  defstruct [:checkpoints, :cursor]

  @type t :: %__MODULE__{
          checkpoints: [Checkpoint.t()],
          cursor: Cursor.t() | nil
        }

  @doc """
  Parse a CheckpointsListResponse from a map with string or atom keys.
  """
  @spec from_map(map()) :: t()
  def from_map(%{} = map) do
    checkpoints_raw = Map.get(map, "checkpoints") || Map.get(map, :checkpoints) || []
    cursor_raw = Map.get(map, "cursor") || Map.get(map, :cursor)

    %__MODULE__{
      checkpoints: Enum.map(checkpoints_raw, &Checkpoint.from_map/1),
      cursor: Cursor.from_map(cursor_raw)
    }
  end
end
