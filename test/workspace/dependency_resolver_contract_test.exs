defmodule Pristine.Workspace.DependencyResolverContractTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @resolver_source Path.expand("../../build_support/dependency_resolver.exs", __DIR__)

  test "the shared dependency resolver can be required from multiple checkout paths", %{
    tmp_dir: tmp_dir
  } do
    first_path = checkout_resolver_path(tmp_dir, "first")
    second_path = checkout_resolver_path(tmp_dir, "second")
    source = File.read!(@resolver_source)

    File.mkdir_p!(Path.dirname(first_path))
    File.mkdir_p!(Path.dirname(second_path))
    File.write!(first_path, source)
    File.write!(second_path, source)

    script = """
    Code.require_file(#{inspect(first_path)})
    Code.require_file(#{inspect(second_path)})
    IO.inspect(Pristine.Build.DependencyResolver.pristine_codegen())
    """

    {output, 0} =
      System.cmd(System.find_executable("elixir") || "elixir", ["-e", script],
        stderr_to_stdout: true
      )

    refute output =~ "redefining module Pristine.Build.DependencyResolver"
    assert output =~ ~s(branch: "main")
    assert output =~ ~s(subdir: "apps/pristine_codegen")
  end

  defp checkout_resolver_path(tmp_dir, checkout_name) do
    Path.join([tmp_dir, checkout_name, "build_support", "dependency_resolver.exs"])
  end
end
