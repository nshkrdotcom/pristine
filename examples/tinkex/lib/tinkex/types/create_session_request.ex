defmodule Tinkex.Types.CreateSessionRequest do
  @moduledoc """
  Request type for creating a new Tinkex session.

  Sessions are the top-level container for training runs and sampling operations.
  A session tracks metadata, tags, and SDK version for observability.
  """

  @enforce_keys [:tags, :sdk_version]
  @derive {Jason.Encoder, only: [:tags, :user_metadata, :sdk_version, :type]}
  defstruct [:tags, :user_metadata, :sdk_version, type: "create_session"]

  @type t :: %__MODULE__{
          tags: [String.t()],
          user_metadata: map() | nil,
          sdk_version: String.t(),
          type: String.t()
        }

  @doc """
  Creates a new CreateSessionRequest with the given options.

  ## Options
    * `:tags` - List of string tags for the session (required)
    * `:sdk_version` - SDK version string (required)
    * `:user_metadata` - Optional map of user-defined metadata

  ## Examples

      iex> CreateSessionRequest.new(tags: ["prod"], sdk_version: "0.3.0")
      %CreateSessionRequest{tags: ["prod"], sdk_version: "0.3.0", type: "create_session"}
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    tags = Keyword.fetch!(opts, :tags)
    sdk_version = Keyword.fetch!(opts, :sdk_version)
    user_metadata = Keyword.get(opts, :user_metadata)

    %__MODULE__{
      tags: tags,
      sdk_version: sdk_version,
      user_metadata: user_metadata
    }
  end
end
