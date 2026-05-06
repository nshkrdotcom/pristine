defmodule Pristine.Workspace.MonorepoContractTest do
  use ExUnit.Case, async: true

  alias Pristine.Workspace.MixProject, as: WorkspaceMixProject

  @required_aliases [
    :"monorepo.deps.get",
    :"monorepo.format",
    :"monorepo.compile",
    :"monorepo.test",
    :"monorepo.credo",
    :"monorepo.dialyzer",
    :"monorepo.docs",
    :"mr.deps.get",
    :"mr.format",
    :"mr.compile",
    :"mr.test",
    :"mr.credo",
    :"mr.dialyzer",
    :"mr.docs",
    :quality,
    :"docs.all",
    :ci
  ]

  @expected_monorepo_aliases [
    {:"monorepo.deps.get", ["blitz.workspace.impact deps_get --"]},
    {:"monorepo.format", ["blitz.workspace.impact format --"]},
    {:"monorepo.compile", ["blitz.workspace.impact compile --"]},
    {:"monorepo.test", ["blitz.workspace.impact test --"]},
    {:"monorepo.credo", ["blitz.workspace.impact credo --"]},
    {:"monorepo.dialyzer", ["compile", "dialyzer --force-check"]},
    {:"monorepo.docs", ["blitz.workspace.impact docs --"]}
  ]

  defp dep_opts(deps, app) do
    Enum.find_value(deps, fn
      {^app, opts} when is_list(opts) -> opts
      {^app, _requirement, opts} when is_list(opts) -> opts
      _ -> nil
    end) || flunk("missing dependency #{inspect(app)}")
  end

  test "root mix project is an unpublished monorepo tooling app" do
    config = WorkspaceMixProject.project()

    assert config[:app] == :pristine_workspace
    assert config[:package] == nil

    aliases = Keyword.get(config, :aliases, [])

    assert Enum.all?(@required_aliases, &Keyword.has_key?(aliases, &1))

    for {alias_name, commands} <- @expected_monorepo_aliases do
      assert Keyword.fetch!(aliases, alias_name) == commands
    end

    assert Keyword.fetch!(aliases, :quality) == [
             "monorepo.credo --strict",
             "monorepo.dialyzer"
           ]

    assert Keyword.fetch!(aliases, :"docs.all") == ["monorepo.docs"]

    assert Keyword.fetch!(aliases, :ci) == [
             "monorepo.format --check-formatted",
             "monorepo.compile",
             "monorepo.test",
             "monorepo.credo --strict",
             "monorepo.dialyzer",
             "monorepo.docs"
           ]

    workspace = Keyword.fetch!(config, :blitz_workspace)

    assert workspace[:root] == __DIR__ |> Path.join("../../") |> Path.expand()
    assert workspace[:projects] == [".", "apps/*"]
    assert workspace[:parallelism][:multiplier] == :auto
    assert Keyword.fetch!(workspace[:tasks], :test)[:color] == true
    assert config[:description] =~ "Tooling root"
  end

  test "root dependencies point at Blitz and the split workspace apps" do
    deps = WorkspaceMixProject.project()[:deps]

    blitz_opts = dep_opts(deps, :blitz)
    assert blitz_opts[:runtime] == false

    runtime_opts = dep_opts(deps, :pristine)
    assert runtime_opts[:path] == "apps/pristine_runtime"

    codegen_opts = dep_opts(deps, :pristine_codegen)
    assert codegen_opts[:path] == "apps/pristine_codegen"

    testkit_opts = dep_opts(deps, :pristine_provider_testkit)
    assert testkit_opts[:path] == "apps/pristine_provider_testkit"
  end

  test "root dialyzer config includes shared workspace beam paths" do
    dialyzer = WorkspaceMixProject.project()[:dialyzer]
    build_path = Path.join("_build", to_string(Mix.env()))

    assert :blitz in dialyzer[:plt_add_apps]
    assert Path.join([build_path, "lib", "pristine_workspace", "ebin"]) in dialyzer[:paths]
    assert Path.join([build_path, "lib", "pristine", "ebin"]) in dialyzer[:paths]
    assert Path.join([build_path, "lib", "pristine_codegen", "ebin"]) in dialyzer[:paths]

    assert Path.join([build_path, "lib", "pristine_provider_testkit", "ebin"]) in dialyzer[:paths]
  end
end
