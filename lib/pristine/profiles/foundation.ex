defmodule Pristine.Profiles.Foundation do
  @moduledoc """
  Build Foundation-backed production contexts and optional telemetry exporters.

  This profile sits above the low-level `Pristine.context/1` constructor and
  turns the existing ports/adapters surface into an explicit production runtime:

  - retry via Foundation-backed adapters
  - shared rate-limit learning via Foundation backoff windows
  - circuit breaking via Foundation circuit breakers
  - structured telemetry event names
  - optional Dispatch-based admission control

  The profile keeps `Pristine.context/1` available as the low-level escape hatch.
  Use this module when you want a cohesive runtime over the Foundation and
  TelemetryReporter dependencies without rebuilding the same context wiring in
  every client SDK.
  """

  alias Pristine.Core.Context
  alias Pristine.TelemetryReporterSupport

  @feature_keys [:retry, :rate_limit, :circuit_breaker, :telemetry, :admission_control]
  @default_telemetry_namespace [:pristine]
  @default_retry_opts [max_attempts: 2]
  @telemetry_suffixes %{
    request_start: [:request, :start],
    request_stop: [:request, :stop],
    request_exception: [:request, :exception],
    stream_start: [:stream, :start],
    stream_connected: [:stream, :connected],
    stream_error: [:stream, :error]
  }

  @type option :: {atom(), term()}
  @type feature_option :: false | true | module() | [option()]

  @doc """
  Build a Foundation-backed `Pristine.Core.Context`.

  Feature options are supplied at the top level:

  - `retry`
  - `rate_limit`
  - `circuit_breaker`
  - `telemetry`
  - `admission_control`

  All other options are forwarded to `Pristine.context/1`.
  """
  @spec context([option()]) :: Context.t()
  def context(opts \\ []) when is_list(opts) do
    {feature_opts, context_opts} = Keyword.split(opts, @feature_keys)

    retry = normalize_retry(Keyword.get(feature_opts, :retry))
    rate_limit = normalize_feature(Keyword.get(feature_opts, :rate_limit), rate_limit_defaults())

    circuit_breaker =
      normalize_feature(Keyword.get(feature_opts, :circuit_breaker), circuit_breaker_defaults())

    telemetry = normalize_telemetry(Keyword.get(feature_opts, :telemetry))
    admission_control = normalize_admission_control(Keyword.get(feature_opts, :admission_control))

    context_opts
    |> Keyword.put(:retry, retry.adapter)
    |> merge_keyword(:retry_opts, retry.opts)
    |> merge_map(:retry_policies, retry.policies)
    |> Keyword.put(:rate_limiter, rate_limit.adapter)
    |> merge_keyword(:rate_limit_opts, rate_limit.opts)
    |> Keyword.put(:circuit_breaker, circuit_breaker.adapter)
    |> merge_keyword(:circuit_breaker_opts, circuit_breaker.opts)
    |> Keyword.put(:telemetry, telemetry.adapter)
    |> merge_map(:telemetry_events, telemetry.events)
    |> merge_map(:telemetry_metadata, telemetry.metadata)
    |> Keyword.put(:admission_control, admission_control.adapter)
    |> merge_keyword(:admission_opts, admission_control.opts)
    |> Keyword.put_new(:result_classifier, Pristine.Adapters.ResultClassifier.HTTP)
    |> Pristine.context()
  end

  @doc """
  Convenience child spec for running a TelemetryReporter instance under supervision.
  """
  @spec reporter_child_spec([option()]) :: Supervisor.child_spec()
  def reporter_child_spec(opts) when is_list(opts) do
    case TelemetryReporterSupport.fetch() do
      {:ok, reporter} ->
        if function_exported?(reporter, :child_spec, 1) do
          reporter.child_spec(opts)
        else
          TelemetryReporterSupport.raise_missing!()
        end

      {:error, :missing_dependency} ->
        TelemetryReporterSupport.raise_missing!()
    end
  end

  @doc """
  Start a TelemetryReporter instance directly.
  """
  @spec start_reporter([option()]) ::
          GenServer.on_start() | {:error, :missing_dependency}
  def start_reporter(opts) when is_list(opts) do
    Foundation.Telemetry.start_reporter(opts)
  end

  @doc """
  Return the telemetry events that should be attached to a reporter for a context.
  """
  @spec reporter_events(Context.t()) :: [[atom()]]
  def reporter_events(%Context{} = context) do
    context.telemetry_events
    |> normalize_reporter_events(context.telemetry)
    |> Enum.uniq()
  end

  @doc """
  Attach a TelemetryReporter handler.

  When given a `Context`, this derives the event list from `context.telemetry_events`
  unless `:events` is supplied explicitly.
  """
  @spec attach_reporter(Context.t(), [option()]) ::
          {:ok, term()} | {:error, :missing_dependency}
  def attach_reporter(%Context{} = context, opts) when is_list(opts) do
    events =
      case Keyword.get(opts, :events) do
        nil -> reporter_events(context)
        explicit -> normalize_reporter_events(explicit, context.telemetry)
      end

    attach_reporter_with_events(opts, events)
  end

  @doc """
  Attach a TelemetryReporter handler with an explicit event list.
  """
  @spec attach_reporter([option()]) :: {:ok, term()} | {:error, :missing_dependency}
  def attach_reporter(opts) when is_list(opts) do
    events =
      opts
      |> Keyword.fetch!(:events)
      |> normalize_reporter_events(nil)

    attach_reporter_with_events(opts, events)
  end

  @doc """
  Detach a previously attached TelemetryReporter handler.
  """
  @spec detach_reporter(term()) :: :ok | {:error, :not_found} | {:error, :missing_dependency}
  def detach_reporter(handler_id) do
    Foundation.Telemetry.detach_reporter(handler_id)
  end

  @doc """
  Build the default structured telemetry event map for a namespace.
  """
  @spec default_telemetry_events([atom()]) :: map()
  def default_telemetry_events(namespace \\ @default_telemetry_namespace)
      when is_list(namespace) do
    Enum.into(@telemetry_suffixes, %{}, fn {key, suffix} -> {key, namespace ++ suffix} end)
  end

  defp attach_reporter_with_events(_opts, []),
    do: raise(ArgumentError, "at least one telemetry event is required to attach a reporter")

  defp attach_reporter_with_events(opts, events) do
    opts
    |> Keyword.put(:events, events)
    |> Foundation.Telemetry.attach_reporter()
  end

  defp normalize_retry(false) do
    %{
      adapter: Pristine.Adapters.Retry.Noop,
      opts: [],
      policies: %{}
    }
  end

  defp normalize_retry(nil) do
    %{
      adapter: Pristine.Adapters.Retry.Foundation,
      opts: @default_retry_opts,
      policies: %{}
    }
  end

  defp normalize_retry(true), do: normalize_retry(nil)

  defp normalize_retry(adapter) when is_atom(adapter) do
    %{
      adapter: adapter,
      opts: @default_retry_opts,
      policies: %{}
    }
  end

  defp normalize_retry(opts) when is_list(opts) do
    if feature_enabled?(opts) do
      {policies, opts} = Keyword.pop(opts, :policies, %{})
      {retry_opts, opts} = Keyword.pop(opts, :opts, [])
      {adapter, opts} = Keyword.pop(opts, :adapter, Pristine.Adapters.Retry.Foundation)
      opts = Keyword.delete(opts, :enabled)

      passthrough_opts =
        @default_retry_opts
        |> Keyword.merge(opts)
        |> Keyword.merge(retry_opts)

      %{
        adapter: adapter,
        opts: passthrough_opts,
        policies: normalize_policies(policies)
      }
    else
      normalize_retry(false)
    end
  end

  defp normalize_retry(other) do
    raise ArgumentError, "invalid retry feature: #{inspect(other)}"
  end

  defp normalize_feature(false, defaults), do: disabled_feature(defaults.noop_adapter)
  defp normalize_feature(nil, defaults), do: enabled_feature(defaults.adapter, defaults.opts)
  defp normalize_feature(true, defaults), do: enabled_feature(defaults.adapter, defaults.opts)

  defp normalize_feature(adapter, defaults) when is_atom(adapter) do
    enabled_feature(adapter, defaults.opts)
  end

  defp normalize_feature(opts, defaults) when is_list(opts) do
    if feature_enabled?(opts) do
      {adapter, opts} = Keyword.pop(opts, :adapter, defaults.adapter)
      opts = Keyword.delete(opts, :enabled)
      enabled_feature(adapter, Keyword.merge(defaults.opts, opts))
    else
      disabled_feature(defaults.noop_adapter)
    end
  end

  defp normalize_feature(other, _defaults) do
    raise ArgumentError, "invalid Foundation feature: #{inspect(other)}"
  end

  defp normalize_telemetry(false) do
    %{
      adapter: Pristine.Adapters.Telemetry.Noop,
      events: %{},
      metadata: %{}
    }
  end

  defp normalize_telemetry(nil) do
    %{
      adapter: Pristine.Adapters.Telemetry.Foundation,
      events: default_telemetry_events(),
      metadata: %{}
    }
  end

  defp normalize_telemetry(true), do: normalize_telemetry(nil)

  defp normalize_telemetry(adapter) when is_atom(adapter) do
    %{
      adapter: adapter,
      events: default_telemetry_events(),
      metadata: %{}
    }
  end

  defp normalize_telemetry(opts) when is_list(opts) do
    if feature_enabled?(opts) do
      {adapter, opts} = Keyword.pop(opts, :adapter, Pristine.Adapters.Telemetry.Foundation)
      {namespace, opts} = Keyword.pop(opts, :namespace, @default_telemetry_namespace)
      {events, opts} = Keyword.pop(opts, :events, %{})
      {metadata, opts} = Keyword.pop(opts, :metadata, %{})
      _opts = Keyword.delete(opts, :enabled)

      normalized_namespace =
        case namespace do
          list when is_list(list) ->
            list

          nil ->
            @default_telemetry_namespace

          other ->
            raise ArgumentError,
                  "telemetry namespace must be a list of atoms, got: #{inspect(other)}"
        end

      %{
        adapter: adapter,
        events:
          Map.merge(default_telemetry_events(normalized_namespace), normalize_event_map(events)),
        metadata: normalize_metadata_map(metadata)
      }
    else
      normalize_telemetry(false)
    end
  end

  defp normalize_telemetry(other) do
    raise ArgumentError, "invalid telemetry feature: #{inspect(other)}"
  end

  defp normalize_admission_control(false),
    do: disabled_feature(Pristine.Adapters.AdmissionControl.Noop)

  defp normalize_admission_control(nil),
    do: disabled_feature(Pristine.Adapters.AdmissionControl.Noop)

  defp normalize_admission_control(true) do
    raise ArgumentError, "dispatch option is required when admission control is enabled"
  end

  defp normalize_admission_control(adapter) when is_atom(adapter) do
    enabled_feature(adapter, [])
  end

  defp normalize_admission_control(opts) when is_list(opts) do
    if feature_enabled?(opts) do
      {adapter, opts} =
        Keyword.pop(opts, :adapter, Pristine.Adapters.AdmissionControl.Dispatch)

      opts = Keyword.delete(opts, :enabled)

      if Keyword.has_key?(opts, :dispatch) do
        enabled_feature(adapter, opts)
      else
        raise ArgumentError, "dispatch option is required when admission control is enabled"
      end
    else
      disabled_feature(Pristine.Adapters.AdmissionControl.Noop)
    end
  end

  defp normalize_admission_control(other) do
    raise ArgumentError, "invalid admission control feature: #{inspect(other)}"
  end

  defp normalize_policies(policies) when is_map(policies), do: policies
  defp normalize_policies(nil), do: %{}

  defp normalize_policies(other),
    do: raise(ArgumentError, "retry policies must be a map, got: #{inspect(other)}")

  defp normalize_event_map(events) when is_map(events), do: events
  defp normalize_event_map(nil), do: %{}

  defp normalize_event_map(other) do
    raise ArgumentError, "telemetry events must be a map, got: #{inspect(other)}"
  end

  defp normalize_metadata_map(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata_map(nil), do: %{}

  defp normalize_metadata_map(other) do
    raise ArgumentError, "telemetry metadata must be a map, got: #{inspect(other)}"
  end

  defp normalize_reporter_events(%Context{} = context, _telemetry_adapter) do
    reporter_events(context)
  end

  defp normalize_reporter_events(events, telemetry_adapter) when is_map(events) do
    events
    |> Map.values()
    |> normalize_reporter_events(telemetry_adapter)
  end

  defp normalize_reporter_events([], _telemetry_adapter), do: []

  defp normalize_reporter_events([head | _] = events, telemetry_adapter) when is_atom(head) do
    [normalize_single_event(events, telemetry_adapter)]
  end

  defp normalize_reporter_events(events, telemetry_adapter) when is_list(events) do
    events
    |> Enum.map(&normalize_single_event(&1, telemetry_adapter))
    |> Enum.reject(&(&1 == []))
  end

  defp normalize_reporter_events(other, _telemetry_adapter) do
    raise ArgumentError, "telemetry events must be a list or map, got: #{inspect(other)}"
  end

  defp normalize_single_event(event, _telemetry_adapter) when is_list(event), do: event

  defp normalize_single_event(event, Pristine.Adapters.Telemetry.Foundation) when is_atom(event),
    do: [:pristine, event]

  defp normalize_single_event(event, _telemetry_adapter) when is_atom(event), do: [event]

  defp enabled_feature(adapter, opts), do: %{adapter: adapter, opts: opts}
  defp disabled_feature(adapter), do: %{adapter: adapter, opts: []}

  defp feature_enabled?(opts), do: Keyword.get(opts, :enabled, true)

  defp rate_limit_defaults do
    %{
      adapter: Pristine.Adapters.RateLimit.BackoffWindow,
      noop_adapter: Pristine.Adapters.RateLimit.Noop,
      opts: []
    }
  end

  defp circuit_breaker_defaults do
    %{
      adapter: Pristine.Adapters.CircuitBreaker.Foundation,
      noop_adapter: Pristine.Adapters.CircuitBreaker.Noop,
      opts: []
    }
  end

  defp merge_keyword(opts, _key, []), do: opts

  defp merge_keyword(opts, key, additional) do
    existing = Keyword.get(opts, key, [])
    Keyword.put(opts, key, Keyword.merge(existing, additional))
  end

  defp merge_map(opts, _key, map) when map == %{}, do: opts

  defp merge_map(opts, key, additional) do
    existing = Keyword.get(opts, key, %{})
    Keyword.put(opts, key, Map.merge(existing, additional))
  end
end
