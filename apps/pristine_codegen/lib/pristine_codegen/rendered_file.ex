defmodule PristineCodegen.RenderedFile do
  @moduledoc """
  Rendered provider file with a relative repo path and deterministic contents.
  """

  @type kind :: :code | :artifact

  @type t :: %__MODULE__{
          kind: kind(),
          relative_path: String.t(),
          contents: String.t()
        }

  @enforce_keys [:kind, :relative_path, :contents]
  defstruct [:kind, :relative_path, :contents]
end
