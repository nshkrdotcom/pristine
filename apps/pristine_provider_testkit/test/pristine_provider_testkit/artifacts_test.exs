defmodule PristineProviderTestkit.ArtifactsTest do
  use ExUnit.Case, async: true

  alias PristineProviderTestkit.Artifacts

  test "returns only missing artifact paths" do
    existing = __ENV__.file
    missing = Path.join(System.tmp_dir!(), "pristine-provider-testkit-missing-artifact")

    assert Artifacts.missing_paths([existing, missing]) == [missing]
  end
end
