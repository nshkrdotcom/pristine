defmodule Pristine.Workspace.BlitzWorkspaceTest do
  use ExUnit.Case, async: true

  alias Pristine.Workspace.MixProject, as: WorkspaceMixProject

  test "enumerates the tooling-root projects in stable order" do
    assert Blitz.MixWorkspace.project_paths() == [
             ".",
             "apps/pristine_codegen",
             "apps/pristine_provider_testkit",
             "apps/pristine_runtime"
           ]
  end

  test "builds task args for each supported workspace task" do
    config = WorkspaceMixProject.project()

    assert Blitz.MixWorkspace.task_args(config, :compile, []) == [
             "compile",
             "--warnings-as-errors"
           ]

    assert Blitz.MixWorkspace.task_args(config, :test, ["--seed", "0"]) == [
             "test",
             "--color",
             "--seed",
             "0"
           ]

    assert Blitz.MixWorkspace.task_args(config, :format, ["--check-formatted"]) == [
             "format",
             "--check-formatted"
           ]
  end

  test "uses env-specific build paths for child commands" do
    config = WorkspaceMixProject.project()

    test_env =
      Map.new(Blitz.MixWorkspace.command_env(config, "apps/pristine_runtime", :test))

    compile_env =
      Map.new(Blitz.MixWorkspace.command_env(config, "apps/pristine_codegen", :compile))

    assert test_env["MIX_DEPS_PATH"] ==
             Path.expand("apps/pristine_runtime/deps", Blitz.MixWorkspace.root_dir())

    assert test_env["MIX_BUILD_PATH"] ==
             Path.expand("apps/pristine_runtime/_build/test", Blitz.MixWorkspace.root_dir())

    assert test_env["MIX_LOCKFILE"] ==
             Path.expand("apps/pristine_runtime/mix.lock", Blitz.MixWorkspace.root_dir())

    assert compile_env["MIX_BUILD_PATH"] ==
             Path.expand("apps/pristine_codegen/_build/dev", Blitz.MixWorkspace.root_dir())
  end

  test "extracts runner arguments without disturbing mix task arguments" do
    assert Blitz.MixWorkspace.split_runner_args(["--max-concurrency", "4", "--strict"]) ==
             {["--strict"], [max_concurrency: 4]}

    assert Blitz.MixWorkspace.split_runner_args(["-j", "2", "--seed", "0"]) ==
             {["--seed", "0"], [max_concurrency: 2]}

    assert Blitz.MixWorkspace.split_runner_args(["--max-concurrency=3", "--check-formatted"]) ==
             {["--check-formatted"], [max_concurrency: 3]}
  end
end
