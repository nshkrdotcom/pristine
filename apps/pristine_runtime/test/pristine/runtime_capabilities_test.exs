defmodule Pristine.RuntimeCapabilitiesTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Pristine.Core.{Context, Request, Response}
  alias Pristine.RuntimeCapabilities

  defmodule LegacyTransport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def send(%Request{}, %Context{}), do: {:ok, %Response{status: 204, headers: %{}, body: ""}}
  end

  defmodule EmptyTransport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def capabilities(%Context{}), do: %{}

    @impl true
    def send(%Request{}, %Context{}), do: {:ok, %Response{status: 204, headers: %{}, body: ""}}
  end

  defmodule MalformedTransport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def capabilities(%Context{}),
      do: %{unary_cancellation: 1, cancellation_cleanup: {:supported, 1}, bounded_queue: "secret"}

    @impl true
    def send(%Request{}, %Context{}), do: {:ok, %Response{status: 204, headers: %{}, body: ""}}
  end

  defmodule ProbeTransport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def capabilities(%Context{transport_opts: opts}) do
      Kernel.send(Keyword.fetch!(opts, :test_pid), :capabilities_called)
      %{unary_cancellation: :unsupported}
    end

    @impl true
    def send(%Request{}, %Context{transport_opts: opts}) do
      Kernel.send(Keyword.fetch!(opts, :test_pid), :transport_send)
      {:ok, %Response{status: 204, headers: %{}, body: ""}}
    end
  end

  defmodule DeclaringTransport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def capabilities(%Context{}) do
      %{
        unary_cancellation: :supported,
        cancellation_cleanup: true,
        bounded_queue: {:supported, 32}
      }
    end

    @impl true
    def send(%Request{}, %Context{}), do: {:ok, %Response{status: 204, headers: %{}, body: ""}}
  end

  test "missing capability callback fails closed as unverified" do
    report = RuntimeCapabilities.transport(Context.new(transport: LegacyTransport))

    assert report.adapter == LegacyTransport
    assert report.capabilities.unary_cancellation.status == :unverified
    assert report.capabilities.cancellation_cleanup.status == :unverified
  end

  test "empty and malformed advertisements fail closed" do
    empty = RuntimeCapabilities.transport(Context.new(transport: EmptyTransport))
    malformed = RuntimeCapabilities.transport(Context.new(transport: MalformedTransport))

    assert empty.capabilities.unary_cancellation.status == :unverified
    assert empty.capabilities.cancellation_cleanup.status == :unverified
    assert malformed.capabilities.unary_cancellation.status == :unverified
    assert malformed.capabilities.cancellation_cleanup.status == :unverified
    assert malformed.capabilities.bounded_queue.status == :unverified
  end

  test "supported declarations and numeric bounds are normalized without context data" do
    context =
      Context.new(
        transport: DeclaringTransport,
        transport_opts: [authorization: "do-not-expose"],
        headers: %{"authorization" => "do-not-expose"}
      )

    report = RuntimeCapabilities.transport(context)

    assert report.capabilities.unary_cancellation == %{status: :supported}
    assert report.capabilities.cancellation_cleanup == %{status: :supported}
    assert report.capabilities.bounded_queue == %{status: :supported, value: 32}
    refute inspect(report) =~ "do-not-expose"
  end

  test "capability query invokes only the side-effect-free capability callback" do
    context = Context.new(transport: ProbeTransport, transport_opts: [test_pid: self()])

    report = RuntimeCapabilities.transport(context)

    assert report.capabilities.unary_cancellation.status == :unsupported
    assert_received :capabilities_called
    refute_received :transport_send
  end

  test "client queries use the same provider-neutral transport report" do
    context = Context.new(transport: DeclaringTransport)
    client = Pristine.Client.from_context(context)

    assert RuntimeCapabilities.transport(client) == RuntimeCapabilities.transport(context)
    assert RuntimeCapabilities.supported?(client, :unary_cancellation)
    refute RuntimeCapabilities.supported?(client, :max_response_bytes)
  end

  test "built-in Finch does not claim cancellation before acceptance proof exists" do
    report =
      RuntimeCapabilities.transport(Context.new(transport: Pristine.Adapters.Transport.Finch))

    assert report.capabilities.unary_cancellation.status == :unsupported
    assert report.capabilities.cancellation_cleanup.status == :unsupported
  end
end
