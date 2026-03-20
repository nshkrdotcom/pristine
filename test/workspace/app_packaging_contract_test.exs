defmodule Pristine.Workspace.AppPackagingContractTest do
  use ExUnit.Case, async: true

  defp project_config(path, module) do
    path
    |> Path.join("mix.exs")
    |> Path.expand()
    |> Code.require_file()

    module.project()
  end

  defp has_dep?(deps, app) do
    Enum.any?(deps, fn
      {^app, _opts} -> true
      {^app, _requirement, _opts} -> true
      _ -> false
    end)
  end

  test "runtime app stays independently publishable as the pristine package" do
    config = project_config("apps/pristine_runtime", Pristine.Runtime.MixProject)

    assert config[:app] == :pristine
    assert config[:package][:name] == "pristine"

    deps = config[:deps]

    refute has_dep?(deps, :pristine_codegen)
    refute has_dep?(deps, :pristine_provider_testkit)
  end

  test "codegen app publishes independently from the runtime package" do
    config = project_config("apps/pristine_codegen", Pristine.Codegen.MixProject)

    assert config[:app] == :pristine_codegen
    assert config[:package][:name] == "pristine_codegen"
  end

  test "provider testkit exists as a separate unpublished workspace app" do
    config =
      project_config("apps/pristine_provider_testkit", Pristine.ProviderTestkit.MixProject)

    assert config[:app] == :pristine_provider_testkit
    assert config[:package] == nil
  end
end
