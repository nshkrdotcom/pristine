defmodule Mix.Tasks.Pristine.ValidateTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Pristine.Validate

  @valid_fixture "test/fixtures/valid_manifest.json"
  @invalid_fixture "test/fixtures/invalid_manifest.json"

  describe "run/1" do
    test "validates a correct manifest file" do
      output =
        capture_io(fn ->
          Validate.run(["--manifest", @valid_fixture])
        end)

      assert output =~ "valid" or output =~ "Valid"
    end

    test "reports errors for invalid manifest" do
      output =
        capture_io(:stderr, fn ->
          try do
            Validate.run(["--manifest", @invalid_fixture])
          catch
            :exit, _ -> :ok
          end
        end)

      assert output =~ "failed" or output =~ "required"
    end

    test "handles missing manifest file" do
      output =
        capture_io(:stderr, fn ->
          try do
            Validate.run(["--manifest", "nonexistent.json"])
          catch
            :exit, _ -> :ok
          end
        end)

      assert output =~ "not found"
    end

    test "supports --format json option" do
      output =
        capture_io(fn ->
          Validate.run(["--manifest", @valid_fixture, "--format", "json"])
        end)

      # Should be valid JSON
      assert {:ok, _} = Jason.decode(String.trim(output))
    end

    test "requires --manifest argument" do
      {stdout, stderr} =
        capture_io_both(fn ->
          try do
            Validate.run([])
          catch
            :exit, _ -> :ok
          end
        end)

      combined = stdout <> stderr
      assert combined =~ "manifest" or combined =~ "required" or combined =~ "Usage"
    end
  end

  defp capture_io_both(fun) do
    stderr =
      capture_io(:stderr, fn ->
        stdout = capture_io(fun)
        send(self(), {:stdout, stdout})
      end)

    receive do
      {:stdout, stdout} -> {stdout, stderr}
    after
      100 -> {"", stderr}
    end
  end
end
