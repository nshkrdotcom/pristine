defmodule Pristine.Ports.Future do
  @moduledoc """
  Port for future/async result polling.

  Futures represent deferred computations that may not be immediately
  available. This port defines the interface for polling a server-side
  future until it completes.

  ## Poll Options

    * `:poll_interval_ms` - Base interval between polls (default: 1000)
    * `:max_poll_time_ms` - Maximum time to poll before timing out (default: 300000)
    * `:backoff` - Backoff strategy: `:none`, `:linear`, or `:exponential`
    * `:on_state_change` - Callback function when poll state changes

  ## Example Implementation

      defmodule MyAdapter do
        @behaviour Pristine.Ports.Future

        @impl true
        def poll(request_id, context, opts) do
          task = Task.async(fn -> poll_loop(request_id, context, opts) end)
          {:ok, task}
        end

        @impl true
        def await(task, timeout) do
          Task.await(task, timeout)
        end
      end
  """

  alias Pristine.Core.Context

  @type poll_opts :: [
          poll_interval_ms: non_neg_integer(),
          max_poll_time_ms: non_neg_integer() | :infinity,
          backoff: :none | :linear | :exponential,
          on_state_change: (map() -> :ok) | nil,
          retrieve_endpoint: atom() | String.t()
        ]

  @doc """
  Start polling for a future result.

  Returns a Task that will eventually resolve to the result.

  ## Parameters

    * `request_id` - The ID of the future request to poll
    * `context` - Runtime context with transport configuration
    * `opts` - Polling options

  ## Returns

    * `{:ok, Task.t()}` - Polling task started
    * `{:error, term()}` - Failed to start polling
  """
  @callback poll(request_id :: String.t(), Context.t(), poll_opts()) ::
              {:ok, Task.t()} | {:error, term()}

  @doc """
  Await the result of a polling task.

  ## Parameters

    * `task` - The polling task returned by `poll/3`
    * `timeout` - How long to wait for the task to complete

  ## Returns

    * `{:ok, term()}` - Polling completed with result
    * `{:error, term()}` - Polling failed or timed out
  """
  @callback await(Task.t(), timeout()) ::
              {:ok, term()} | {:error, term()}
end
