defmodule Pristine.SDK.Profiles.Foundation do
  @moduledoc """
  SDK-facing Foundation-backed runtime profile contract.
  """

  alias Pristine.Profiles.Foundation, as: RuntimeFoundation
  alias Pristine.SDK.Context

  @type option :: RuntimeFoundation.option()
  @type feature_option :: RuntimeFoundation.feature_option()

  @spec context([option()]) :: Context.t()
  defdelegate context(opts \\ []), to: RuntimeFoundation

  @spec reporter_child_spec([option()]) :: Supervisor.child_spec()
  defdelegate reporter_child_spec(opts), to: RuntimeFoundation

  @spec start_reporter([option()]) :: GenServer.on_start() | {:error, :missing_dependency}
  defdelegate start_reporter(opts), to: RuntimeFoundation

  @spec reporter_events(Context.t()) :: [[atom()]]
  defdelegate reporter_events(context), to: RuntimeFoundation

  @spec attach_reporter(Context.t(), [option()]) :: {:ok, term()} | {:error, :missing_dependency}
  defdelegate attach_reporter(context, opts), to: RuntimeFoundation

  @spec attach_reporter([option()]) :: {:ok, term()} | {:error, :missing_dependency}
  defdelegate attach_reporter(opts), to: RuntimeFoundation

  @spec detach_reporter(term()) :: :ok | {:error, :not_found} | {:error, :missing_dependency}
  defdelegate detach_reporter(handler_id), to: RuntimeFoundation

  @spec default_telemetry_events([atom()]) :: map()
  defdelegate default_telemetry_events(namespace \\ [:pristine]), to: RuntimeFoundation
end
