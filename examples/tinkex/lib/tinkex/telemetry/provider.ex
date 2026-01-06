defmodule Tinkex.Telemetry.Provider do
  @moduledoc """
  Behaviour for modules that provide telemetry reporter access.

  This behaviour defines a standard interface for any module that can expose
  a telemetry reporter process. It mirrors the Python `TelemetryProvider` protocol.

  ## Usage

  Modules can `use` this behaviour to get a default implementation:

      defmodule MyClient do
        use Tinkex.Telemetry.Provider

        # Default get_telemetry/0 returns nil
        # Override to provide actual reporter:

        @impl Tinkex.Telemetry.Provider
        def get_telemetry do
          # Return the reporter pid or nil
          Process.whereis(:my_telemetry_reporter)
        end
      end

  The default implementation returns `nil`, indicating no telemetry reporter
  is available. Modules should override this to return their reporter pid.

  ## Integration

  This behaviour is used by:
  - `Tinkex.ServiceClient` - exposes session telemetry reporter
  - `Tinkex.TrainingClient` - inherits from service client
  - `Tinkex.SamplingClient` - inherits from service client

  ## Example with Agent State

      defmodule StatefulClient do
        use Tinkex.Telemetry.Provider

        def start_link(reporter_pid) do
          Agent.start_link(fn -> reporter_pid end, name: __MODULE__)
        end

        @impl Tinkex.Telemetry.Provider
        def get_telemetry do
          try do
            Agent.get(__MODULE__, & &1)
          catch
            :exit, _ -> nil
          end
        end
      end
  """

  @doc """
  Get the telemetry reporter pid for this module.

  Returns the pid of the telemetry reporter process, or `nil` if no
  reporter is available or telemetry is disabled.
  """
  @callback get_telemetry() :: pid() | nil

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Tinkex.Telemetry.Provider

      @impl Tinkex.Telemetry.Provider
      def get_telemetry, do: nil

      defoverridable get_telemetry: 0
    end
  end
end
