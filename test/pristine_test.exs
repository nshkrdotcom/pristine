defmodule PristineTest do
  use ExUnit.Case
  doctest Pristine

  test "loads a manifest" do
    input = %{name: "demo", version: "0.1.0", endpoints: [], types: %{}}

    assert {:ok, manifest} = Pristine.load_manifest(input)
    assert manifest.name == "demo"
  end
end
