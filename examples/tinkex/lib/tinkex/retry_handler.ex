defmodule Tinkex.RetryHandler do
  @moduledoc """
  Manages retry state with exponential backoff and jitter.

  ## Configuration

    * `:max_retries` - Maximum retry attempts (default: `:infinity`)
    * `:base_delay_ms` - Base delay in milliseconds (default: 500)
    * `:max_delay_ms` - Maximum delay cap (default: 10_000)
    * `:jitter_pct` - Jitter percentage (default: 0.25)
    * `:progress_timeout_ms` - Timeout for progress (default: 7_200_000)

  ## Usage

      handler = RetryHandler.new(max_retries: 5, base_delay_ms: 100)

      if RetryHandler.retry?(handler, error) do
        delay = RetryHandler.next_delay(handler)
        Process.sleep(delay)
        handler = RetryHandler.increment_attempt(handler)
        # ... retry logic
      end
  """

  alias Tinkex.Error

  @default_max_retries :infinity
  @default_base_delay_ms 500
  @default_max_delay_ms 10_000
  @default_jitter_pct 0.25
  @default_progress_timeout_ms 7_200_000

  defstruct [
    :max_retries,
    :base_delay_ms,
    :max_delay_ms,
    :jitter_pct,
    :progress_timeout_ms,
    :attempt,
    :last_progress_at,
    :start_time
  ]

  @type t :: %__MODULE__{
          max_retries: non_neg_integer() | :infinity,
          base_delay_ms: non_neg_integer(),
          max_delay_ms: non_neg_integer(),
          jitter_pct: float(),
          progress_timeout_ms: non_neg_integer(),
          attempt: non_neg_integer(),
          last_progress_at: integer() | nil,
          start_time: integer()
        }

  @doc """
  Create a new retry handler with the given options.

  ## Options

    * `:max_retries` - Maximum retry attempts (default: `:infinity`)
    * `:base_delay_ms` - Base delay in milliseconds (default: 500)
    * `:max_delay_ms` - Maximum delay cap (default: 10_000)
    * `:jitter_pct` - Jitter percentage 0.0-1.0 (default: 0.25)
    * `:progress_timeout_ms` - Timeout for progress (default: 7_200_000)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now = System.monotonic_time(:millisecond)

    %__MODULE__{
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, @default_base_delay_ms),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, @default_max_delay_ms),
      jitter_pct: Keyword.get(opts, :jitter_pct, @default_jitter_pct),
      progress_timeout_ms: Keyword.get(opts, :progress_timeout_ms, @default_progress_timeout_ms),
      attempt: 0,
      last_progress_at: now,
      start_time: now
    }
  end

  @doc """
  Determine if an error should be retried.

  Returns `false` if max retries reached.
  For `Tinkex.Error` structs, checks `Error.retryable?/1`.
  For other terms, returns `true` by default.
  """
  @spec retry?(t(), Error.t() | term()) :: boolean()
  def retry?(%__MODULE__{attempt: attempt, max_retries: max}, _error)
      when is_integer(max) and attempt >= max do
    false
  end

  def retry?(%__MODULE__{}, %Error{} = error) do
    Error.retryable?(error)
  end

  def retry?(%__MODULE__{}, _error), do: true

  @doc """
  Calculate the next delay with exponential backoff and jitter.

  The delay is calculated as: `base_delay_ms * 2^attempt`, capped at `max_delay_ms`,
  with random jitter applied within `[-jitter_pct, +jitter_pct]` of the delay.
  """
  @spec next_delay(t()) :: non_neg_integer()
  def next_delay(%__MODULE__{} = handler) do
    base = handler.base_delay_ms * :math.pow(2, handler.attempt)
    capped = min(base, handler.max_delay_ms)

    if handler.jitter_pct > 0 do
      # Jitter in the range [-jitter_pct, +jitter_pct] of the capped delay
      jitter = capped * handler.jitter_pct * (2 * :rand.uniform() - 1)

      capped
      |> Kernel.+(jitter)
      |> max(0)
      |> min(handler.max_delay_ms)
      |> round()
    else
      round(capped)
    end
  end

  @doc """
  Record progress to reset the progress timeout.
  """
  @spec record_progress(t()) :: t()
  def record_progress(%__MODULE__{} = handler) do
    %{handler | last_progress_at: System.monotonic_time(:millisecond)}
  end

  @doc """
  Check if the progress timeout has been exceeded.

  Returns `false` on the first attempt or if `last_progress_at` is nil.
  """
  @spec progress_timeout?(t()) :: boolean()
  def progress_timeout?(%__MODULE__{attempt: 0}), do: false
  def progress_timeout?(%__MODULE__{last_progress_at: nil}), do: false

  def progress_timeout?(%__MODULE__{} = handler) do
    elapsed = System.monotonic_time(:millisecond) - handler.last_progress_at
    elapsed > handler.progress_timeout_ms
  end

  @doc """
  Increment the attempt counter.
  """
  @spec increment_attempt(t()) :: t()
  def increment_attempt(%__MODULE__{} = handler) do
    %{handler | attempt: handler.attempt + 1}
  end

  @doc """
  Get elapsed time since the handler was created.
  """
  @spec elapsed_ms(t()) :: non_neg_integer()
  def elapsed_ms(%__MODULE__{} = handler) do
    System.monotonic_time(:millisecond) - handler.start_time
  end
end
