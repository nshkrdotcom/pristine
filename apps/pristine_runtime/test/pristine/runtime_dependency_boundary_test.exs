defmodule Pristine.RuntimeDependencyBoundaryTest do
  use ExUnit.Case, async: true

  test "optional integrations are not hard runtime applications" do
    applications = Application.spec(:pristine, :applications) || []

    refute :oauth2 in applications
    refute :telemetry_reporter in applications
    refute :tiktoken_ex in applications
    refute :mox in applications
    refute :plug in applications
    refute :plug_cowboy in applications
    refute :bandit in applications
  end
end
