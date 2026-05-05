defmodule Pristine.TelemetryReporterSupport do
  @moduledoc false

  @missing_dependency_message """
  telemetry_reporter dependency is not available; add {:telemetry_reporter, "~> 0.1.0"} to use reporter-backed telemetry
  """

  @spec module() :: module()
  def module do
    Application.get_env(:pristine, :telemetry_reporter_module) ||
      TelemetryReporter
  end

  @spec fetch() :: {:ok, module()} | {:error, :missing_dependency}
  def fetch do
    reporter = module()

    if Code.ensure_loaded?(reporter) do
      {:ok, reporter}
    else
      {:error, :missing_dependency}
    end
  end

  @spec raise_missing!() :: no_return()
  def raise_missing! do
    raise RuntimeError, @missing_dependency_message
  end
end
