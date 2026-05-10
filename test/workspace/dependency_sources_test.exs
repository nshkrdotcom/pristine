defmodule Pristine.Workspace.DependencySourcesTest do
  use ExUnit.Case, async: false

  @project_root Path.expand("../..", __DIR__)
  @runtime_root Path.join(@project_root, "apps/pristine_runtime")
  @codegen_root Path.join(@project_root, "apps/pristine_codegen")
  @testkit_root Path.join(@project_root, "apps/pristine_provider_testkit")

  setup do
    original_argv = System.argv()

    on_exit(fn ->
      System.argv(original_argv)
    end)

    :ok
  end

  test "deps.get inside the workspace keeps sibling paths available" do
    System.argv(["deps.get"])

    assert {:execution_plane, opts} = DependencySources.dep(:execution_plane, @runtime_root)
    assert opts[:path] == Path.expand("../execution_plane/core/execution_plane", @project_root)

    assert {:execution_plane_http, opts} =
             DependencySources.dep(:execution_plane_http, @runtime_root)

    assert opts[:path] ==
             Path.expand("../execution_plane/protocols/execution_plane_http", @project_root)

    assert {:pristine, opts} = DependencySources.dep(:pristine, @project_root)
    assert opts[:path] == Path.join(@project_root, "apps/pristine_runtime")

    assert {:pristine_codegen, opts} = DependencySources.dep(:pristine_codegen, @project_root)
    assert opts[:path] == Path.join(@project_root, "apps/pristine_codegen")

    assert {:pristine_provider_testkit, opts} =
             DependencySources.dep(:pristine_provider_testkit, @project_root)

    assert opts[:path] == Path.join(@project_root, "apps/pristine_provider_testkit")
  end

  test "publishing commands skip workspace paths" do
    System.argv(["hex.build"])

    assert {:execution_plane, "~> 0.1.0"} =
             DependencySources.dep(:execution_plane, @runtime_root)

    assert {:execution_plane_http, "~> 0.1.0"} =
             DependencySources.dep(:execution_plane_http, @runtime_root)

    assert {:pristine, "~> 0.2.1"} = DependencySources.dep(:pristine, @project_root)
    assert {:pristine, "~> 0.2.1"} = DependencySources.dep(:pristine, @codegen_root)

    assert {:pristine_codegen, "~> 0.1.0"} =
             DependencySources.dep(:pristine_codegen, @project_root)

    assert {:pristine_codegen, "~> 0.1.0"} =
             DependencySources.dep(:pristine_codegen, @testkit_root)

    assert {:pristine_provider_testkit, "~> 0.1.0"} =
             DependencySources.dep(:pristine_provider_testkit, @project_root)
  end

  test "github fallback metadata keeps package subdirectories precise" do
    assert %{deps: deps} =
             @runtime_root
             |> Path.join("build_support/dependency_sources.config.exs")
             |> eval_config!()

    assert deps.execution_plane.github == %{
             repo: "nshkrdotcom/execution_plane",
             branch: "main",
             subdir: "core/execution_plane"
           }

    assert deps.execution_plane_http.github == %{
             repo: "nshkrdotcom/execution_plane",
             branch: "main",
             subdir: "protocols/execution_plane_http"
           }

    assert %{deps: deps} =
             @project_root
             |> Path.join("build_support/dependency_sources.config.exs")
             |> eval_config!()

    assert deps.pristine_codegen.github == %{
             repo: "nshkrdotcom/pristine",
             branch: "main",
             subdir: "apps/pristine_codegen"
           }
  end

  defp eval_config!(path) do
    {config, _binding} = Code.eval_file(path)
    config
  end
end
