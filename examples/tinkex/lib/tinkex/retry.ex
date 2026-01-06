defmodule Tinkex.Retry do
  @moduledoc """
  Retry operations with exponential backoff and telemetry.

  Executes a function with automatic retries on failure. Uses `RetryHandler`
  to manage retry state, delays, and decide if errors are retryable.

  ## Usage

      # Simple retry with defaults
      {:ok, result} = Retry.with_retry(fn ->
        make_api_call()
      end)

      # Custom retry configuration
      {:ok, result} = Retry.with_retry(
        fn -> make_api_call() end,
        handler: RetryHandler.new(max_retries: 5, base_delay_ms: 100),
        telemetry_metadata: %{operation: "fetch_model"}
      )

  ## Telemetry Events

  The following telemetry events are emitted:

    * `[:tinkex, :retry, :attempt, :start]` - Before each attempt
    * `[:tinkex, :retry, :attempt, :stop]` - After successful attempt
    * `[:tinkex, :retry, :attempt, :retry]` - When retrying after failure
    * `[:tinkex, :retry, :attempt, :failed]` - When giving up after max retries
  """

  alias Tinkex.Error
  alias Tinkex.RetryHandler

  @telemetry_start [:tinkex, :retry, :attempt, :start]
  @telemetry_stop [:tinkex, :retry, :attempt, :stop]
  @telemetry_retry [:tinkex, :retry, :attempt, :retry]
  @telemetry_failed [:tinkex, :retry, :attempt, :failed]

  @doc """
  Execute a function with retry logic.

  ## Options

    * `:handler` - A `RetryHandler.t()` (default: `RetryHandler.new()`)
    * `:telemetry_metadata` - Additional metadata for telemetry events (default: `%{}`)

  ## Returns

    * `{:ok, result}` - On success
    * `{:error, error}` - After exhausting retries or on non-retryable error
  """
  @spec with_retry((-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) do
    handler = Keyword.get(opts, :handler, RetryHandler.new())
    metadata = Keyword.get(opts, :telemetry_metadata, %{})

    do_retry(fun, handler, metadata)
  end

  defp do_retry(fun, handler, metadata) do
    if RetryHandler.progress_timeout?(handler) do
      {:error, Error.new(:api_timeout, "Progress timeout exceeded")}
    else
      execute_attempt(fun, handler, metadata)
    end
  end

  defp execute_attempt(fun, handler, metadata) do
    attempt_metadata = Map.put(metadata, :attempt, handler.attempt)

    :telemetry.execute(
      @telemetry_start,
      %{system_time: System.system_time()},
      attempt_metadata
    )

    start_time = System.monotonic_time()

    result =
      try do
        fun.()
      rescue
        exception ->
          {:exception, exception, __STACKTRACE__}
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, value} ->
        :telemetry.execute(
          @telemetry_stop,
          %{duration: duration},
          Map.put(attempt_metadata, :result, :ok)
        )

        {:ok, value}

      {:error, error} ->
        handle_error(fun, error, handler, metadata, attempt_metadata, duration)

      {:exception, exception, _stacktrace} ->
        handle_exception(fun, exception, handler, metadata, attempt_metadata, duration)
    end
  end

  defp handle_error(fun, error, handler, metadata, attempt_metadata, duration) do
    if RetryHandler.retry?(handler, error) do
      delay = RetryHandler.next_delay(handler)

      :telemetry.execute(
        @telemetry_retry,
        %{duration: duration, delay_ms: delay},
        Map.merge(attempt_metadata, %{error: error})
      )

      Process.sleep(delay)

      handler = RetryHandler.increment_attempt(handler)

      do_retry(fun, handler, metadata)
    else
      :telemetry.execute(
        @telemetry_failed,
        %{duration: duration},
        Map.merge(attempt_metadata, %{result: :failed, error: error})
      )

      {:error, error}
    end
  end

  defp handle_exception(fun, exception, handler, metadata, attempt_metadata, duration) do
    if RetryHandler.retry?(handler, exception) do
      delay = RetryHandler.next_delay(handler)

      :telemetry.execute(
        @telemetry_retry,
        %{duration: duration, delay_ms: delay},
        Map.merge(attempt_metadata, %{exception: exception})
      )

      Process.sleep(delay)

      handler = RetryHandler.increment_attempt(handler)

      do_retry(fun, handler, metadata)
    else
      :telemetry.execute(
        @telemetry_failed,
        %{duration: duration},
        Map.merge(attempt_metadata, %{result: :exception, exception: exception})
      )

      {:error, Error.new(:request_failed, Exception.message(exception))}
    end
  end
end
