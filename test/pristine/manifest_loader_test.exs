defmodule Pristine.Manifest.LoaderTest do
  use ExUnit.Case, async: true

  alias Pristine.Manifest

  test "loads manifest from json file" do
    path = Path.join(System.tmp_dir!(), "pristine_manifest.json")
    on_exit(fn -> File.rm(path) end)

    json = ~s({"name":"demo","version":"0.1.0","endpoints":[],"types":{}})
    File.write!(path, json)

    assert {:ok, manifest} = Manifest.load_file(path)
    assert manifest.name == "demo"
  end

  test "loads manifest from exs file" do
    path = Path.join(System.tmp_dir!(), "pristine_manifest.exs")
    on_exit(fn -> File.rm(path) end)

    File.write!(path, "%{name: \"demo\", version: \"0.1.0\", endpoints: [], types: %{}}")

    assert {:ok, manifest} = Manifest.load_file(path)
    assert manifest.name == "demo"
  end

  test "rejects exs files that do not evaluate to a manifest map" do
    path = Path.join(System.tmp_dir!(), "pristine_invalid_manifest.exs")
    on_exit(fn -> File.rm(path) end)

    File.write!(path, "[1, 2, 3]")

    assert {:error, {:invalid_elixir_manifest, [1, 2, 3]}} = Manifest.load_file(path)
  end

  test "loads manifest from yaml file" do
    path = Path.join(System.tmp_dir!(), "pristine_manifest.yaml")
    on_exit(fn -> File.rm(path) end)

    yaml = """
    name: demo
    version: 0.1.0
    endpoints: []
    types: {}
    """

    File.write!(path, yaml)

    assert {:ok, manifest} = Manifest.load_file(path)
    assert manifest.name == "demo"
    assert manifest.version == "0.1.0"
  end
end
