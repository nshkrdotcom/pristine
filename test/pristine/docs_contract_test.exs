defmodule Pristine.DocsContractTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)
  @getting_started_path Path.expand("../../guides/getting-started.md", __DIR__)
  @manifests_guide_path Path.expand("../../guides/manifests.md", __DIR__)

  test "README uses the generated client accessor API that actually exists" do
    readme = File.read!(@readme_path)

    assert readme =~ "\"resource\": \"users\""
    assert readme =~ "resource = MyAPI.Client.users(client)"
    assert readme =~ "{:ok, user} = MyAPI.Users.get(resource, \"user-123\")"
    refute readme =~ "client.users()"
  end

  test "getting started guide uses the generated client accessor API that actually exists" do
    guide = File.read!(@getting_started_path)

    assert guide =~ "\"resource\": \"users\""
    assert guide =~ "resource = MyAPI.Client.users(client)"
    assert guide =~ "{:ok, user} = MyAPI.Users.get(resource, \"user-123\")"
    refute guide =~ "client.users()"
    refute guide =~ "Elixir script format"
  end

  test "manifest guide documents the simplified contract only" do
    guide = File.read!(@manifests_guide_path)

    assert guide =~ "| `retry_policies` | object | Named retry policy definitions |"
    assert guide =~ "Use `{param}` syntax:"
    refute guide =~ "| `policies` | object | Generic policy definitions |"
    refute guide =~ "Use `{param}` or `:param` syntax:"
  end
end
