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

    content = """
    %{name: \"demo\", version: \"0.1.0\", endpoints: [], types: %{}}
    """

    File.write!(path, content)

    assert {:ok, manifest} = Manifest.load_file(path)
    assert manifest.version == "0.1.0"
  end
end
