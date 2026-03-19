defmodule Pristine.Workspace.MonorepoContractTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Monorepo.Compile
  alias Mix.Tasks.Monorepo.Credo
  alias Mix.Tasks.Monorepo.Deps.Get
  alias Mix.Tasks.Monorepo.Dialyzer
  alias Mix.Tasks.Monorepo.Docs
  alias Mix.Tasks.Monorepo.Format
  alias Mix.Tasks.Monorepo.Test
  alias Pristine.Workspace.MixProject, as: WorkspaceMixProject

  @required_monorepo_aliases [
    :"mr.deps.get",
    :"mr.format",
    :"mr.compile",
    :"mr.test",
    :"mr.credo",
    :"mr.dialyzer",
    :"mr.docs",
    :ci
  ]

  @required_monorepo_tasks [
    Get,
    Format,
    Compile,
    Test,
    Credo,
    Dialyzer,
    Docs
  ]

  defp dep_opts(deps, app) do
    Enum.find_value(deps, fn
      {^app, opts} when is_list(opts) -> opts
      _ -> nil
    end) || flunk("missing dependency #{inspect(app)}")
  end

  test "root mix project is an unpublished monorepo tooling app" do
    config = WorkspaceMixProject.project()

    assert config[:app] == :pristine_workspace
    assert config[:package] == nil

    aliases = Keyword.get(config, :aliases, [])

    assert Enum.all?(@required_monorepo_aliases, &Keyword.has_key?(aliases, &1))

    workspace = Keyword.fetch!(config, :blitz_workspace)

    assert workspace[:root] == __DIR__ |> Path.join("../../") |> Path.expand()
    assert "." in workspace[:projects]
    assert "apps/*" in workspace[:projects]

    assert Enum.all?(@required_monorepo_tasks, fn module ->
             Code.ensure_loaded?(module) and function_exported?(module, :run, 1)
           end)
  end

  test "root path dependencies point at the split workspace apps" do
    deps = WorkspaceMixProject.project()[:deps]

    runtime_opts = dep_opts(deps, :pristine)
    assert runtime_opts[:path] == "apps/pristine_runtime"

    codegen_opts = dep_opts(deps, :pristine_codegen)
    assert codegen_opts[:path] == "apps/pristine_codegen"

    testkit_opts = dep_opts(deps, :pristine_provider_testkit)
    assert testkit_opts[:path] == "apps/pristine_provider_testkit"
  end
end
