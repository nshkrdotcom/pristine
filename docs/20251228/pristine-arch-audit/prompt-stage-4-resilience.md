# Stage 4: Resilience Completion Implementation Prompt

**Estimated Effort**: 4-6 days
**Prerequisites**: Stage 0 Complete (can run parallel to Stages 1-3)
**Goal**: All tests pass, no warnings, no errors, no dialyzer errors, no `mix credo --strict` errors

---

## Context

You are implementing Stage 4 of the Pristine architecture buildout. This stage focuses on completing the resilience infrastructure including Retry-After header parsing, connection limiting via semaphores, enhanced telemetry, and structured error types.

---

## Required Reading

### Architecture Documentation
```
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/overview.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/04-transport-retry-telemetry.md
```

### Foundation Source Files
```
/home/home/p/g/n/foundation/lib/foundation/retry.ex
/home/home/p/g/n/foundation/lib/foundation/backoff.ex
/home/home/p/g/n/foundation/lib/foundation/circuit_breaker.ex
/home/home/p/g/n/foundation/lib/foundation/rate_limit/backoff_window.ex
/home/home/p/g/n/foundation/lib/foundation/semaphore/counting.ex
/home/home/p/g/n/foundation/lib/foundation/telemetry.ex
```

### Pristine Adapter Files
```
/home/home/p/g/n/pristine/lib/pristine/adapters/retry/foundation.ex
/home/home/p/g/n/pristine/lib/pristine/adapters/circuit_breaker/foundation.ex
/home/home/p/g/n/pristine/lib/pristine/adapters/rate_limit/backoff_window.ex
/home/home/p/g/n/pristine/lib/pristine/adapters/telemetry/reporter.ex
```

### Reference: Tinker Retry Logic
```
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py (lines 683-706)
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/retry_handler.py
```

---

## Tasks

### Task 4.1: Retry-After Header Parsing (1 day)

**Files to Create**:
- `/home/home/p/g/n/foundation/lib/foundation/retry/http.ex`
- `/home/home/p/g/n/foundation/test/foundation/retry/http_test.exs`

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/adapters/retry/foundation.ex`

**TDD Steps**:

1. **Write Tests First**:

```elixir
# /home/home/p/g/n/foundation/test/foundation/retry/http_test.exs
defmodule Foundation.Retry.HTTPTest do
  use ExUnit.Case, async: true

  alias Foundation.Retry.HTTP

  describe "parse_retry_after/1" do
    test "parses retry-after-ms header (milliseconds)" do
      headers = %{"retry-after-ms" => "500"}
      assert HTTP.parse_retry_after(headers) == 500
    end

    test "parses retry-after header (seconds)" do
      headers = %{"retry-after" => "5"}
      assert HTTP.parse_retry_after(headers) == 5_000
    end

    test "prefers retry-after-ms over retry-after" do
      headers = %{
        "retry-after-ms" => "100",
        "retry-after" => "10"
      }
      assert HTTP.parse_retry_after(headers) == 100
    end

    test "handles HTTP date format" do
      # 10 seconds in the future
      future = DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")

      headers = %{"retry-after" => future}
      result = HTTP.parse_retry_after(headers)

      # Should be approximately 10 seconds (10000ms) +/- 1 second
      assert result >= 9_000 and result <= 11_000
    end

    test "returns nil for missing headers" do
      assert HTTP.parse_retry_after(%{}) == nil
      assert HTTP.parse_retry_after(%{"other" => "header"}) == nil
    end

    test "returns nil for invalid values" do
      assert HTTP.parse_retry_after(%{"retry-after" => "not-a-number"}) == nil
      assert HTTP.parse_retry_after(%{"retry-after-ms" => "abc"}) == nil
    end

    test "handles case-insensitive header names" do
      headers = %{"Retry-After" => "5"}
      assert HTTP.parse_retry_after(headers) == 5_000
    end

    test "caps very large retry values" do
      headers = %{"retry-after" => "999999"}
      result = HTTP.parse_retry_after(headers)
      # Should cap at 1 hour
      assert result <= 3_600_000
    end
  end

  describe "should_retry?/1" do
    test "returns true for retriable status codes" do
      assert HTTP.should_retry?(%{status: 408}) == true
      assert HTTP.should_retry?(%{status: 429}) == true
      assert HTTP.should_retry?(%{status: 500}) == true
      assert HTTP.should_retry?(%{status: 502}) == true
      assert HTTP.should_retry?(%{status: 503}) == true
      assert HTTP.should_retry?(%{status: 504}) == true
    end

    test "returns false for non-retriable status codes" do
      assert HTTP.should_retry?(%{status: 200}) == false
      assert HTTP.should_retry?(%{status: 400}) == false
      assert HTTP.should_retry?(%{status: 401}) == false
      assert HTTP.should_retry?(%{status: 404}) == false
    end

    test "respects x-should-retry header" do
      # Header overrides status code
      assert HTTP.should_retry?(%{status: 400, headers: %{"x-should-retry" => "true"}}) == true
      assert HTTP.should_retry?(%{status: 500, headers: %{"x-should-retry" => "false"}}) == false
    end
  end
end
```

2. **Implement HTTP Retry Helpers**:

```elixir
# /home/home/p/g/n/foundation/lib/foundation/retry/http.ex
defmodule Foundation.Retry.HTTP do
  @moduledoc """
  HTTP-specific retry utilities.
  """

  @retriable_status_codes [408, 429, 500, 502, 503, 504]
  @max_retry_delay_ms 3_600_000  # 1 hour

  @doc """
  Parse retry delay from HTTP response headers.

  Supports:
  - `retry-after-ms` (milliseconds, non-standard but precise)
  - `retry-after` (seconds or HTTP date)

  Returns delay in milliseconds, or nil if no valid header.
  """
  @spec parse_retry_after(map()) :: non_neg_integer() | nil
  def parse_retry_after(headers) when is_map(headers) do
    headers = normalize_header_keys(headers)

    cond do
      ms = headers["retry-after-ms"] ->
        parse_integer(ms)

      value = headers["retry-after"] ->
        parse_retry_after_value(value)

      true ->
        nil
    end
  end

  @doc """
  Determine if a response should be retried.
  """
  @spec should_retry?(map()) :: boolean()
  def should_retry?(%{headers: headers} = response) when is_map(headers) do
    headers = normalize_header_keys(headers)

    case headers["x-should-retry"] do
      "true" -> true
      "false" -> false
      _ -> status_retriable?(response)
    end
  end

  def should_retry?(response), do: status_retriable?(response)

  # Private

  defp normalize_header_keys(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)
  end

  defp parse_retry_after_value(value) do
    case parse_integer(value) do
      nil -> parse_http_date(value)
      seconds -> min(seconds * 1000, @max_retry_delay_ms)
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_), do: nil

  defp parse_http_date(date_string) do
    case Timex.parse(date_string, "{RFC1123}") do
      {:ok, datetime} ->
        now = DateTime.utc_now()
        diff_ms = DateTime.diff(datetime, now, :millisecond)
        if diff_ms > 0, do: min(diff_ms, @max_retry_delay_ms), else: nil

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp status_retriable?(%{status: status}) when status in @retriable_status_codes, do: true
  defp status_retriable?(_), do: false
end
```

3. **Wire into Pristine Retry Adapter**:

Update `/home/home/p/g/n/pristine/lib/pristine/adapters/retry/foundation.ex` to use `HTTP.parse_retry_after/1`.

---

### Task 4.2: Connection Limiting (Semaphore Port) (2 days)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/ports/semaphore.ex`
- `/home/home/p/g/n/pristine/lib/pristine/adapters/semaphore/counting.ex`
- `/home/home/p/g/n/pristine/test/pristine/adapters/semaphore/counting_test.exs`

**TDD Steps**:

1. **Write Tests**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/adapters/semaphore/counting_test.exs
defmodule Pristine.Adapters.Semaphore.CountingTest do
  use ExUnit.Case, async: false

  alias Pristine.Adapters.Semaphore.Counting

  setup do
    # Ensure clean state
    :ok
  end

  describe "with_permit/3" do
    test "limits concurrent executions" do
      name = :test_sem_#{:rand.uniform(100_000)}
      Counting.init(name, 2)

      # Track concurrent executions
      counter = :counters.new(1, [:atomics])
      max_concurrent = :counters.new(1, [:atomics])

      tasks = for _ <- 1..10 do
        Task.async(fn ->
          Counting.with_permit(name, 5_000, fn ->
            :counters.add(counter, 1, 1)
            current = :counters.get(counter, 1)

            # Update max if current is higher
            max = :counters.get(max_concurrent, 1)
            if current > max, do: :counters.put(max_concurrent, 1, current)

            Process.sleep(50)
            :counters.sub(counter, 1, 1)
            :ok
          end)
        end)
      end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &(&1 == :ok))

      # Max concurrent should never exceed limit
      assert :counters.get(max_concurrent, 1) <= 2
    end

    test "returns timeout error when limit reached" do
      name = :test_sem_timeout_#{:rand.uniform(100_000)}
      Counting.init(name, 1)

      # Acquire the only permit
      task = Task.async(fn ->
        Counting.with_permit(name, :infinity, fn ->
          Process.sleep(1_000)
          :ok
        end)
      end)

      # Wait for task to acquire permit
      Process.sleep(50)

      # Try to acquire with short timeout - should fail
      assert {:error, :timeout} = Counting.with_permit(name, 10, fn -> :ok end)

      Task.shutdown(task, :brutal_kill)
    end

    test "releases permit on exception" do
      name = :test_sem_exception_#{:rand.uniform(100_000)}
      Counting.init(name, 1)

      # This should acquire and release permit despite exception
      catch_error(
        Counting.with_permit(name, 1_000, fn ->
          raise "test error"
        end)
      )

      # Should be able to acquire again
      assert :ok = Counting.with_permit(name, 100, fn -> :ok end)
    end
  end

  describe "available/1" do
    test "returns current available permits" do
      name = :test_sem_avail_#{:rand.uniform(100_000)}
      Counting.init(name, 5)

      assert Counting.available(name) == 5

      Counting.with_permit(name, 1_000, fn ->
        assert Counting.available(name) == 4
      end)

      assert Counting.available(name) == 5
    end
  end
end
```

2. **Create Port**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/ports/semaphore.ex
defmodule Pristine.Ports.Semaphore do
  @moduledoc """
  Port for connection/concurrency limiting.
  """

  @callback init(name :: term(), limit :: pos_integer()) :: :ok
  @callback with_permit(name :: term(), timeout :: timeout(), (-> result)) ::
              result | {:error, :timeout}
            when result: term()
  @callback acquire(name :: term(), timeout :: timeout()) :: :ok | {:error, :timeout}
  @callback release(name :: term()) :: :ok
  @callback available(name :: term()) :: non_neg_integer()
end
```

3. **Implement Adapter**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/adapters/semaphore/counting.ex
defmodule Pristine.Adapters.Semaphore.Counting do
  @moduledoc """
  Counting semaphore adapter using Foundation.Semaphore.Counting.
  """

  @behaviour Pristine.Ports.Semaphore

  alias Foundation.Semaphore.Counting, as: FoundationSemaphore

  @impl true
  def init(name, limit) when is_integer(limit) and limit > 0 do
    FoundationSemaphore.new(name, limit)
    :ok
  end

  @impl true
  def with_permit(name, timeout, fun) when is_function(fun, 0) do
    case acquire(name, timeout) do
      :ok ->
        try do
          fun.()
        after
          release(name)
        end

      {:error, :timeout} = error ->
        error
    end
  end

  @impl true
  def acquire(name, timeout) do
    FoundationSemaphore.acquire(name, timeout)
  end

  @impl true
  def release(name) do
    FoundationSemaphore.release(name)
  end

  @impl true
  def available(name) do
    FoundationSemaphore.available(name)
  end
end
```

4. **Wire into Pipeline** (modify `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex`).

---

### Task 4.3: Enhanced Telemetry Port (1-2 days)

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/ports/telemetry.ex`
- `/home/home/p/g/n/pristine/lib/pristine/adapters/telemetry/foundation.ex`

**Files to Create**:
- `/home/home/p/g/n/pristine/test/pristine/adapters/telemetry/foundation_test.exs`

**TDD Steps**:

1. **Write Tests**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/adapters/telemetry/foundation_test.exs
defmodule Pristine.Adapters.Telemetry.FoundationTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Telemetry.Foundation, as: TelemetryAdapter

  describe "measure/3" do
    test "times function execution and returns result" do
      result = TelemetryAdapter.measure(:test_event, %{key: "value"}, fn ->
        Process.sleep(10)
        :test_result
      end)

      assert result == :test_result
    end

    test "emits telemetry event with duration" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-#{ref}",
        [:pristine, :test_measure],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      TelemetryAdapter.measure(:test_measure, %{id: 123}, fn ->
        Process.sleep(10)
        :ok
      end)

      assert_receive {:telemetry, measurements, metadata}
      assert is_integer(measurements[:duration])
      assert measurements[:duration] >= 10_000_000  # At least 10ms in native time
      assert metadata[:id] == 123

      :telemetry.detach("test-#{ref}")
    end
  end

  describe "emit_counter/2" do
    test "emits counter event" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-counter-#{ref}",
        [:pristine, :test_counter],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:counter, measurements, metadata})
        end,
        nil
      )

      TelemetryAdapter.emit_counter(:test_counter, %{type: "request"})

      assert_receive {:counter, %{count: 1}, %{type: "request"}}

      :telemetry.detach("test-counter-#{ref}")
    end
  end

  describe "emit_gauge/3" do
    test "emits gauge event with value" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-gauge-#{ref}",
        [:pristine, :test_gauge],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:gauge, measurements, metadata})
        end,
        nil
      )

      TelemetryAdapter.emit_gauge(:test_gauge, 42.5, %{metric: "cpu"})

      assert_receive {:gauge, %{value: 42.5}, %{metric: "cpu"}}

      :telemetry.detach("test-gauge-#{ref}")
    end
  end
end
```

2. **Update Port**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/ports/telemetry.ex
defmodule Pristine.Ports.Telemetry do
  @moduledoc """
  Telemetry port for observability.
  """

  @callback emit(event :: atom(), metadata :: map(), measurements :: map()) :: :ok
  @callback measure(event :: atom(), metadata :: map(), fun :: (-> result)) :: result
            when result: term()
  @callback emit_counter(event :: atom(), metadata :: map()) :: :ok
  @callback emit_gauge(event :: atom(), value :: number(), metadata :: map()) :: :ok

  @optional_callbacks [measure: 3, emit_counter: 2, emit_gauge: 3]
end
```

3. **Implement Foundation Adapter**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/adapters/telemetry/foundation.ex
defmodule Pristine.Adapters.Telemetry.Foundation do
  @moduledoc """
  Telemetry adapter using Foundation.Telemetry.
  """

  @behaviour Pristine.Ports.Telemetry

  @impl true
  def emit(event, metadata, measurements) do
    :telemetry.execute([:pristine, event], measurements, metadata)
  end

  @impl true
  def measure(event, metadata, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time
      emit(event, metadata, %{duration: duration})
      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time
        emit(event, Map.put(metadata, :error, true), %{duration: duration})
        reraise e, __STACKTRACE__
    end
  end

  @impl true
  def emit_counter(event, metadata) do
    emit(event, metadata, %{count: 1})
  end

  @impl true
  def emit_gauge(event, value, metadata) do
    emit(event, metadata, %{value: value})
  end
end
```

---

### Task 4.4: Error Module (1 day)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/error.ex`
- `/home/home/p/g/n/pristine/test/pristine/error_test.exs`

**TDD Steps**:

1. **Write Tests**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/error_test.exs
defmodule Pristine.ErrorTest do
  use ExUnit.Case, async: true

  alias Pristine.Error
  alias Pristine.Core.Response

  describe "from_response/1" do
    test "creates bad_request error for 400" do
      response = %Response{status: 400, body: "Bad request"}
      error = Error.from_response(response)

      assert error.type == :bad_request
      assert error.status == 400
    end

    test "creates authentication error for 401" do
      response = %Response{status: 401, body: "Unauthorized"}
      error = Error.from_response(response)

      assert error.type == :authentication
      assert error.status == 401
    end

    test "creates permission_denied error for 403" do
      response = %Response{status: 403}
      error = Error.from_response(response)

      assert error.type == :permission_denied
    end

    test "creates not_found error for 404" do
      response = %Response{status: 404}
      error = Error.from_response(response)

      assert error.type == :not_found
    end

    test "creates rate_limit error for 429" do
      response = %Response{status: 429}
      error = Error.from_response(response)

      assert error.type == :rate_limit
    end

    test "creates internal_server error for 5xx" do
      for status <- [500, 502, 503, 504] do
        response = %Response{status: status}
        error = Error.from_response(response)
        assert error.type == :internal_server
      end
    end

    test "includes response body in error" do
      response = %Response{status: 400, body: ~s({"error": "invalid"})}
      error = Error.from_response(response)

      assert error.body == ~s({"error": "invalid"})
    end
  end

  describe "message/1" do
    test "returns human-readable message" do
      error = %Error{type: :rate_limit, status: 429}
      assert Error.message(error) =~ "rate limit"
    end
  end
end
```

2. **Implement Error Module**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/error.ex
defmodule Pristine.Error do
  @moduledoc """
  Structured error types for API responses.
  """

  alias Pristine.Core.Response

  @type error_type ::
          :bad_request
          | :authentication
          | :permission_denied
          | :not_found
          | :conflict
          | :unprocessable_entity
          | :rate_limit
          | :internal_server
          | :timeout
          | :connection
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          status: integer() | nil,
          message: String.t() | nil,
          body: term(),
          response: Response.t() | nil
        }

  defstruct [:type, :status, :message, :body, :response]

  @doc "Create an error from an HTTP response."
  @spec from_response(Response.t()) :: t()
  def from_response(%Response{status: status} = response) do
    %__MODULE__{
      type: status_to_type(status),
      status: status,
      message: status_to_message(status),
      body: response.body,
      response: response
    }
  end

  @doc "Create a connection error."
  @spec connection_error(term()) :: t()
  def connection_error(reason) do
    %__MODULE__{
      type: :connection,
      message: "Connection failed: #{inspect(reason)}"
    }
  end

  @doc "Create a timeout error."
  @spec timeout_error() :: t()
  def timeout_error do
    %__MODULE__{
      type: :timeout,
      message: "Request timed out"
    }
  end

  @doc "Get a human-readable error message."
  @spec message(t()) :: String.t()
  def message(%__MODULE__{message: msg}) when is_binary(msg), do: msg
  def message(%__MODULE__{type: type}), do: type_to_message(type)

  # Private

  defp status_to_type(400), do: :bad_request
  defp status_to_type(401), do: :authentication
  defp status_to_type(403), do: :permission_denied
  defp status_to_type(404), do: :not_found
  defp status_to_type(409), do: :conflict
  defp status_to_type(422), do: :unprocessable_entity
  defp status_to_type(429), do: :rate_limit
  defp status_to_type(status) when status >= 500, do: :internal_server
  defp status_to_type(_), do: :unknown

  defp status_to_message(400), do: "Bad request"
  defp status_to_message(401), do: "Authentication failed"
  defp status_to_message(403), do: "Permission denied"
  defp status_to_message(404), do: "Resource not found"
  defp status_to_message(409), do: "Conflict"
  defp status_to_message(422), do: "Unprocessable entity"
  defp status_to_message(429), do: "Rate limit exceeded"
  defp status_to_message(status) when status >= 500, do: "Internal server error"
  defp status_to_message(_), do: "Unknown error"

  defp type_to_message(:bad_request), do: "Bad request"
  defp type_to_message(:authentication), do: "Authentication failed"
  defp type_to_message(:permission_denied), do: "Permission denied"
  defp type_to_message(:not_found), do: "Resource not found"
  defp type_to_message(:conflict), do: "Conflict"
  defp type_to_message(:unprocessable_entity), do: "Unprocessable entity"
  defp type_to_message(:rate_limit), do: "Rate limit exceeded"
  defp type_to_message(:internal_server), do: "Internal server error"
  defp type_to_message(:timeout), do: "Request timed out"
  defp type_to_message(:connection), do: "Connection failed"
  defp type_to_message(_), do: "Unknown error"
end
```

---

## Verification Checklist

```bash
# Foundation
cd /home/home/p/g/n/foundation
mix test
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer

# Pristine
cd /home/home/p/g/n/pristine
mix test
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
```

---

## Expected Outcomes

After Stage 4 completion:

1. **Retry-After headers** are parsed and respected
2. **Connection limiting** via semaphores prevents resource exhaustion
3. **Enhanced telemetry** with measure/counter/gauge functions
4. **Structured errors** with status-specific types
5. All resilience patterns from Tinker SDK are supported
