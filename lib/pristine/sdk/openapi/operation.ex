defmodule Pristine.SDK.OpenAPI.Operation do
  @moduledoc """
  SDK-facing helpers injected into generated OpenAPI operation modules.
  """

  alias Pristine.OpenAPI.Operation, as: RuntimeOperation

  @type key_spec :: RuntimeOperation.key_spec()
  @type payload_spec :: RuntimeOperation.payload_spec()
  @type partition_spec :: RuntimeOperation.partition_spec()
  @type partition_t :: RuntimeOperation.partition_t()

  defmacro __using__(_opts) do
    quote do
      import Pristine.SDK.OpenAPI.Operation, only: [partition: 2, render_path: 2]
    end
  end

  @spec partition(map(), partition_spec()) :: partition_t()
  defdelegate partition(params, spec), to: RuntimeOperation

  @spec render_path(String.t(), map()) :: String.t()
  defdelegate render_path(path_template, path_params), to: RuntimeOperation
end
