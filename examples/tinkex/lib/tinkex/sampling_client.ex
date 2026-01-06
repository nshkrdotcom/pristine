defmodule Tinkex.SamplingClient do
  @moduledoc """
  High-level sampling client for text generation.

  A struct-based client that wraps `Tinkex.API.Sampling` with convenient
  async operations and typed responses. For production use with rate limiting
  and dispatch management, consider using the full GenServer-based implementation.

  ## Usage

      config = Tinkex.Config.new(api_key: "tml-key")
      client = Tinkex.SamplingClient.new("sampling-session-123", config)

      # Sample with parameters
      prompt = Tinkex.Types.ModelInput.from_ints([1, 2, 3])
      params = %Tinkex.Types.SamplingParams{max_tokens: 100, temperature: 0.8}
      {:ok, task} = Tinkex.SamplingClient.sample(client, prompt, params)
      {:ok, response} = Task.await(task)

      # Stream tokens
      {:ok, stream} = Tinkex.SamplingClient.sample_stream(client, prompt, params)
      Enum.each(stream, fn event -> IO.inspect(event) end)

  ## Queue State Observation

  The `sample/4` function accepts a `:queue_state_observer` option for
  monitoring rate limiting and queue status:

      observer = fn state, meta ->
        IO.puts("Queue state: \#{state}")
        :ok
      end

      {:ok, task} = SamplingClient.sample(client, prompt, params,
        queue_state_observer: observer
      )
  """

  alias Tinkex.API.Sampling, as: SamplingAPI
  alias Tinkex.Config
  alias Tinkex.Error
  alias Tinkex.Future
  alias Tinkex.Types.{ModelInput, SampledSequence, SamplingParams}

  @enforce_keys [:sampling_session_id, :config]
  defstruct [:sampling_session_id, :config, :sampling_api, :futures_api, :seq_counter]

  @type t :: %__MODULE__{
          sampling_session_id: String.t(),
          config: Config.t(),
          sampling_api: module() | nil,
          futures_api: module() | nil,
          seq_counter: reference() | nil
        }

  @type sample_response :: %{
          sequences: [SampledSequence.t()],
          prompt_logprobs: [float()] | nil,
          topk_prompt_logprobs: [[{integer(), float()}]] | nil,
          type: String.t()
        }

  @doc """
  Create a new SamplingClient.

  ## Options

    * `:sampling_api` - Module implementing sampling API functions (default: `Tinkex.API.Sampling`)
    * `:futures_api` - Module implementing futures polling (default: `Tinkex.Future`)
  """
  @spec new(String.t(), Config.t(), keyword()) :: t()
  def new(sampling_session_id, config, opts \\ []) do
    %__MODULE__{
      sampling_session_id: sampling_session_id,
      config: config,
      sampling_api: Keyword.get(opts, :sampling_api),
      futures_api: Keyword.get(opts, :futures_api),
      seq_counter: :atomics.new(1, [])
    }
  end

  @doc """
  Submit a sample request and return a polling task.

  ## Parameters

    * `client` - SamplingClient instance
    * `prompt` - ModelInput or list of token IDs
    * `sampling_params` - SamplingParams struct
    * `opts` - Options:
      * `:num_samples` - Number of samples to generate (default: 1)
      * `:prompt_logprobs` - Whether to return prompt logprobs
      * `:topk_prompt_logprobs` - Number of top-k logprobs per token
      * `:queue_state_observer` - Callback `fn(state, meta) -> :ok` for queue monitoring

  ## Returns

    * `{:ok, Task.t()}` - Task that resolves to sample response
    * `{:error, Error.t()}` - Error if request submission fails
  """
  @spec sample(t(), ModelInput.t() | [integer()], SamplingParams.t(), keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def sample(%__MODULE__{} = client, prompt, %SamplingParams{} = sampling_params, opts \\ []) do
    seq_id = next_seq_id(client)

    request =
      build_sample_request(client, prompt, sampling_params, seq_id, opts)

    api = sampling_api(client)

    case api.sample_future(client.config, request) do
      {:ok, %{"request_id" => request_id}} ->
        futures = futures_api(client)
        poll_opts = build_poll_opts(opts)
        task = futures.poll(client.config, request_id, poll_opts)
        {:ok, task}

      {:ok, response} ->
        {:error,
         Error.new(:validation, "Unexpected sample_future response: #{inspect(response)}")}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Submit a streaming sample request.

  Returns an enumerable stream of token events.

  ## Parameters

    * `client` - SamplingClient instance
    * `prompt` - ModelInput or list of token IDs
    * `sampling_params` - SamplingParams struct
    * `opts` - Same options as `sample/4` (except queue_state_observer)

  ## Returns

    * `{:ok, Enumerable.t()}` - Stream of token events
    * `{:error, Error.t()}` - Error if request fails
  """
  @spec sample_stream(t(), ModelInput.t() | [integer()], SamplingParams.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def sample_stream(
        %__MODULE__{} = client,
        prompt,
        %SamplingParams{} = sampling_params,
        opts \\ []
      ) do
    seq_id = next_seq_id(client)

    request =
      build_sample_request(client, prompt, sampling_params, seq_id, opts)

    api = sampling_api(client)
    api.sample_stream(client.config, request)
  end

  @doc """
  Compute log probabilities for a prompt.

  ## Parameters

    * `client` - SamplingClient instance
    * `prompt` - ModelInput or list of token IDs
    * `opts` - Options:
      * `:topk_logprobs` - Number of top-k logprobs per token

  ## Returns

    * `{:ok, Task.t()}` - Task that resolves to logprobs response
    * `{:error, Error.t()}` - Error if request submission fails
  """
  @spec compute_logprobs(t(), ModelInput.t() | [integer()], keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def compute_logprobs(%__MODULE__{} = client, prompt, opts \\ []) do
    seq_id = next_seq_id(client)

    request = %{
      sampling_session_id: client.sampling_session_id,
      prompt: normalize_prompt(prompt),
      seq_id: seq_id,
      topk_logprobs: Keyword.get(opts, :topk_logprobs)
    }

    api = sampling_api(client)

    case api.compute_logprobs_future(client.config, request) do
      {:ok, %{"request_id" => request_id}} ->
        futures = futures_api(client)
        poll_opts = build_poll_opts(opts)
        task = futures.poll(client.config, request_id, poll_opts)
        {:ok, task}

      {:ok, response} ->
        {:error,
         Error.new(:validation, "Unexpected compute_logprobs response: #{inspect(response)}")}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Get the next sequence ID for this client.

  Uses atomic increment for thread-safe sequence generation.
  """
  @spec next_seq_id(t()) :: integer()
  def next_seq_id(%__MODULE__{seq_counter: counter}) do
    :atomics.add_get(counter, 1, 1)
  end

  @doc """
  Parse a raw sample response into typed structures.

  ## Parameters

    * `response` - Raw response map from API

  ## Returns

    * `{:ok, sample_response()}` - Parsed response with typed sequences
    * `{:error, Error.t()}` - Parse error
  """
  @spec parse_sample_response(map()) :: {:ok, sample_response()} | {:error, Error.t()}
  def parse_sample_response(%{"sequences" => sequences} = response) do
    parsed_sequences =
      Enum.map(sequences, fn seq ->
        SampledSequence.from_json(seq)
      end)

    {:ok,
     %{
       sequences: parsed_sequences,
       prompt_logprobs: response["prompt_logprobs"],
       topk_prompt_logprobs: response["topk_prompt_logprobs"],
       type: response["type"] || "sample"
     }}
  end

  def parse_sample_response(response) do
    {:error, Error.new(:validation, "Invalid sample response: #{inspect(response)}")}
  end

  # Private helpers

  defp build_sample_request(client, prompt, sampling_params, seq_id, opts) do
    %{
      sampling_session_id: client.sampling_session_id,
      prompt: normalize_prompt(prompt),
      sampling_params: sampling_params,
      seq_id: seq_id,
      num_samples: Keyword.get(opts, :num_samples, 1),
      prompt_logprobs: Keyword.get(opts, :prompt_logprobs),
      topk_prompt_logprobs: Keyword.get(opts, :topk_prompt_logprobs)
    }
  end

  defp normalize_prompt(%ModelInput{} = input), do: ModelInput.to_ints(input)
  defp normalize_prompt(tokens) when is_list(tokens), do: tokens

  defp build_poll_opts(opts) do
    poll_opts = []

    poll_opts =
      case Keyword.get(opts, :queue_state_observer) do
        nil -> poll_opts
        observer -> Keyword.put(poll_opts, :queue_state_observer, observer)
      end

    poll_opts
  end

  defp sampling_api(%__MODULE__{sampling_api: nil}), do: SamplingAPI
  defp sampling_api(%__MODULE__{sampling_api: api}), do: api

  defp futures_api(%__MODULE__{futures_api: nil}), do: Future
  defp futures_api(%__MODULE__{futures_api: api}), do: api

  # ============================================
  # Async Creation
  # ============================================

  alias Tinkex.ServiceClient

  @doc """
  Asynchronously create a SamplingClient from a ServiceClient.

  Returns a Task that resolves to `{:ok, SamplingClient.t()}` or
  `{:error, Error.t()}`.

  This is a convenience wrapper around `ServiceClient.create_sampling_client/2`
  that runs the creation in a separate Task for non-blocking operation.

  ## Parameters

    * `service_client` - ServiceClient instance
    * `opts` - Options passed to `ServiceClient.create_sampling_client/2`:
      * `:base_model` - Base model identifier for new sampling session
      * `:model_path` - Tinker path to existing weights

  ## Examples

      task = SamplingClient.create_async(service_client, base_model: "Qwen/Qwen2.5-7B")
      # Do other work...
      {:ok, sampling_client} = Task.await(task)

  """
  @spec create_async(ServiceClient.t(), keyword()) :: Task.t()
  def create_async(%ServiceClient{} = service_client, opts \\ []) do
    Task.async(fn -> ServiceClient.create_sampling_client(service_client, opts) end)
  end

  # ============================================
  # Queue State Observability
  # ============================================

  alias Tinkex.QueueStateLogger

  @debounce_interval_ms 60_000

  @doc """
  Handle queue state changes with debounced logging.

  Logs warnings for non-active states with automatic debouncing to
  prevent log spam. Uses `:persistent_term` for debounce state tracking.

  ## Parameters

    * `client` - SamplingClient instance
    * `queue_state` - One of `:active`, `:paused_rate_limit`, `:paused_capacity`, `:unknown`

  ## Returns

    * `:ok`
  """
  @spec on_queue_state_change(t(), QueueStateLogger.queue_state()) :: :ok
  def on_queue_state_change(%__MODULE__{} = client, queue_state) do
    on_queue_state_change(client, queue_state, %{})
  end

  @doc """
  Handle queue state changes with metadata and debounced logging.

  ## Parameters

    * `client` - SamplingClient instance
    * `queue_state` - One of `:active`, `:paused_rate_limit`, `:paused_capacity`, `:unknown`
    * `metadata` - Map with optional `:queue_state_reason` key for custom reason

  ## Returns

    * `:ok`
  """
  @spec on_queue_state_change(t(), QueueStateLogger.queue_state(), map()) :: :ok
  def on_queue_state_change(%__MODULE__{} = _client, :active, _metadata) do
    # Don't log for active state
    :ok
  end

  def on_queue_state_change(%__MODULE__{} = client, queue_state, metadata) do
    debounce_key = debounce_key(client)
    last_logged = get_debounce_time(debounce_key)
    server_reason = Map.get(metadata, :queue_state_reason)

    if QueueStateLogger.should_log?(last_logged, @debounce_interval_ms) do
      QueueStateLogger.log_state_change(
        queue_state,
        :sampling,
        client.sampling_session_id,
        server_reason
      )

      set_debounce_time(debounce_key)
    end

    :ok
  end

  @doc """
  Clear the debounce state for this client.

  Allows immediate logging on the next `on_queue_state_change/2` call.
  Useful for cleanup or when forcing a fresh log.

  ## Parameters

    * `client` - SamplingClient instance

  ## Returns

    * `:ok`
  """
  @spec clear_queue_state_debounce(t()) :: :ok
  def clear_queue_state_debounce(%__MODULE__{} = client) do
    debounce_key = debounce_key(client)
    :persistent_term.erase(debounce_key)
    :ok
  rescue
    # Key may not exist
    ArgumentError -> :ok
  end

  # Debounce helpers using :persistent_term

  defp debounce_key(%__MODULE__{sampling_session_id: id}) do
    {:tinkex_sampling_debounce, id}
  end

  defp get_debounce_time(key) do
    :persistent_term.get(key, nil)
  rescue
    ArgumentError -> nil
  end

  defp set_debounce_time(key) do
    :persistent_term.put(key, System.monotonic_time(:millisecond))
  end
end
