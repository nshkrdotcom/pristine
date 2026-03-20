defmodule PristineCodegen.MixTasksTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Pristine.Codegen.Generate
  alias Mix.Tasks.Pristine.Codegen.Ir
  alias Mix.Tasks.Pristine.Codegen.Refresh
  alias Mix.Tasks.Pristine.Codegen.Verify

  @provider "PristineCodegen.TestSupport.SampleProvider"

  test "shared generate, ir, refresh, and verify tasks delegate through the compiler" do
    project_root = tmp_project_root!("mix_tasks")

    Mix.Task.reenable("pristine.codegen.verify")

    assert_raise Mix.Error, ~r/generated artifacts are stale/, fn ->
      capture_io(fn ->
        Verify.run([@provider, "--project-root", project_root])
      end)
    end

    Mix.Task.reenable("pristine.codegen.generate")

    generate_output =
      capture_io(fn ->
        Generate.run([@provider, "--project-root", project_root])
      end)

    assert generate_output =~ "generated WidgetAPI"
    assert File.exists?(Path.join(project_root, "priv/generated/provider_ir.json"))

    Mix.Task.reenable("pristine.codegen.ir")

    ir_output =
      capture_io(fn ->
        Ir.run([@provider, "--project-root", project_root])
      end)

    assert ir_output =~ "\"provider\""
    assert ir_output =~ "\"widget_api\""

    Mix.Task.reenable("pristine.codegen.refresh")

    refresh_output =
      capture_io(fn ->
        Refresh.run([@provider, "--project-root", project_root])
      end)

    assert refresh_output =~ "refreshed WidgetAPI"
    assert File.exists?(Path.join(project_root, "priv/upstream/refreshed.txt"))

    Mix.Task.reenable("pristine.codegen.verify")

    verify_output =
      capture_io(fn ->
        Verify.run([@provider, "--project-root", project_root])
      end)

    assert verify_output =~ "verified WidgetAPI"
  end

  defp tmp_project_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "pristine-codegen-mix-task-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
