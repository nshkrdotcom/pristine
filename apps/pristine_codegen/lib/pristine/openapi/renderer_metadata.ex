defmodule Pristine.OpenAPI.RendererMetadata do
  @moduledoc false

  @type metadata :: keyword()

  @spec put(atom(), metadata()) :: :ok
  def put(profile, metadata) when is_atom(profile) and is_list(metadata) do
    Process.put(key(profile), metadata)
    :ok
  end

  @spec get(atom()) :: metadata()
  def get(profile) when is_atom(profile) do
    Process.get(key(profile), [])
  end

  @spec delete(atom()) :: :ok
  def delete(profile) when is_atom(profile) do
    Process.delete(key(profile))
    :ok
  end

  defp key(profile), do: {__MODULE__, profile}
end
