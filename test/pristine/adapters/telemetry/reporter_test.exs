defmodule Pristine.Adapters.Telemetry.ReporterTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Telemetry.Reporter

  setup do
    original = Application.get_env(:pristine, :telemetry_reporter_module)

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:pristine, :telemetry_reporter_module)
      else
        Application.put_env(:pristine, :telemetry_reporter_module, original)
      end
    end)

    :ok
  end

  test "raises a clear error when telemetry_reporter is unavailable" do
    Application.put_env(:pristine, :telemetry_reporter_module, MissingTelemetryReporter)

    assert_raise RuntimeError, ~r/telemetry_reporter dependency is not available/, fn ->
      Reporter.emit([:pristine, :request, :stop], %{}, %{duration: 1})
    end
  end
end
