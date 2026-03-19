defmodule Pristine.OpenAPI.RendererMetadataTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.RendererMetadata

  test "stores metadata in the current process only" do
    profile = :"renderer_metadata_#{System.unique_integer([:positive])}"

    on_exit(fn -> RendererMetadata.delete(profile) end)

    assert :ok = RendererMetadata.put(profile, schema_specs_by_path: %{"Widget" => %{}})
    assert RendererMetadata.get(profile) == [schema_specs_by_path: %{"Widget" => %{}}]

    assert Task.async(fn -> RendererMetadata.get(profile) end) |> Task.await() == []
  end
end
