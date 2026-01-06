defmodule Tinkex.SamplingClientTest do
  use ExUnit.Case, async: true

  alias Tinkex.SamplingClient
  alias Tinkex.Types.{ModelInput, SamplingParams, SampledSequence}

  defmodule MockSamplingAPI do
    def sample_future(_config, request) do
      seq_id = request["seq_id"] || request[:seq_id]
      {:ok, %{"request_id" => "future-#{seq_id}"}}
    end

    def compute_logprobs_future(_config, request) do
      seq_id = request["seq_id"] || request[:seq_id]
      {:ok, %{"request_id" => "logprobs-#{seq_id}"}}
    end

    def sample_stream(_config, _request) do
      {:ok, Stream.map(1..3, fn i -> %{"token" => i, "type" => "token"} end)}
    end
  end

  defmodule MockFutures do
    def poll(_config, request_id, opts) do
      observer = Keyword.get(opts, :queue_state_observer)

      if observer && is_function(observer, 2) do
        observer.(:active, %{request_id: request_id})
      end

      Task.async(fn ->
        {:ok,
         %{
           "sequences" => [
             %{"tokens" => [1, 2, 3], "stop_reason" => "length"}
           ],
           "type" => "sample"
         }}
      end)
    end
  end

  setup do
    config = %Tinkex.Config{
      base_url: "https://example.com",
      api_key: "tml-test-key",
      timeout: 60_000,
      max_retries: 3
    }

    client =
      SamplingClient.new(
        "sampling-session-123",
        config,
        sampling_api: MockSamplingAPI,
        futures_api: MockFutures
      )

    {:ok, client: client, config: config}
  end

  describe "new/3" do
    test "creates a SamplingClient struct", %{config: config} do
      client = SamplingClient.new("session-123", config)

      assert %SamplingClient{} = client
      assert client.sampling_session_id == "session-123"
      assert client.config == config
    end

    test "accepts optional sampling_api and futures_api modules", %{config: config} do
      client =
        SamplingClient.new("session-123", config,
          sampling_api: MockSamplingAPI,
          futures_api: MockFutures
        )

      assert client.sampling_api == MockSamplingAPI
      assert client.futures_api == MockFutures
    end
  end

  describe "sample/4" do
    test "submits sample request and returns polling task", %{client: client} do
      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{max_tokens: 100, temperature: 0.8}

      {:ok, task} = SamplingClient.sample(client, prompt, params)

      assert %Task{} = task
      {:ok, response} = Task.await(task)
      assert response["sequences"]
    end

    test "accepts raw token list as prompt", %{client: client} do
      params = %SamplingParams{max_tokens: 50}

      {:ok, task} = SamplingClient.sample(client, [1, 2, 3], params)

      assert %Task{} = task
    end

    test "passes queue_state_observer option", %{client: client} do
      test_pid = self()

      observer = fn state, meta ->
        send(test_pid, {:queue_state, state, meta})
        :ok
      end

      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{max_tokens: 100}

      {:ok, task} = SamplingClient.sample(client, prompt, params, queue_state_observer: observer)

      Task.await(task)

      assert_receive {:queue_state, :active, %{request_id: _}}
    end

    test "accepts num_samples option", %{client: client} do
      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{max_tokens: 100}

      {:ok, task} = SamplingClient.sample(client, prompt, params, num_samples: 3)

      assert %Task{} = task
    end

    test "accepts prompt_logprobs option", %{client: client} do
      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{max_tokens: 100}

      {:ok, task} = SamplingClient.sample(client, prompt, params, prompt_logprobs: true)

      assert %Task{} = task
    end
  end

  describe "sample_stream/4" do
    test "returns an enumerable stream", %{client: client} do
      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{max_tokens: 100}

      {:ok, stream} = SamplingClient.sample_stream(client, prompt, params)

      events = Enum.to_list(stream)
      assert length(events) == 3
    end
  end

  describe "compute_logprobs/3" do
    test "submits logprobs request and returns polling task", %{client: client} do
      prompt = ModelInput.from_ints([1, 2, 3])

      {:ok, task} = SamplingClient.compute_logprobs(client, prompt)

      assert %Task{} = task
    end

    test "accepts topk_logprobs option", %{client: client} do
      prompt = ModelInput.from_ints([1, 2, 3])

      {:ok, task} = SamplingClient.compute_logprobs(client, prompt, topk_logprobs: 10)

      assert %Task{} = task
    end
  end

  describe "next_seq_id/1" do
    test "returns incrementing sequence IDs", %{client: client} do
      seq1 = SamplingClient.next_seq_id(client)
      seq2 = SamplingClient.next_seq_id(client)

      assert is_integer(seq1)
      assert is_integer(seq2)
      assert seq2 > seq1
    end
  end

  describe "parse_sample_response/1" do
    test "parses sequences from response" do
      response = %{
        "sequences" => [
          %{"tokens" => [1, 2, 3], "stop_reason" => "length", "logprobs" => [0.1, 0.2, 0.3]},
          %{"tokens" => [4, 5], "stop_reason" => "stop"}
        ],
        "type" => "sample"
      }

      {:ok, parsed} = SamplingClient.parse_sample_response(response)

      assert length(parsed.sequences) == 2
      [seq1, seq2] = parsed.sequences
      assert %SampledSequence{tokens: [1, 2, 3], stop_reason: :length} = seq1
      assert %SampledSequence{tokens: [4, 5], stop_reason: :stop} = seq2
    end

    test "handles prompt_logprobs in response" do
      response = %{
        "sequences" => [%{"tokens" => [1], "stop_reason" => "length"}],
        "prompt_logprobs" => [0.1, 0.2, 0.3],
        "type" => "sample"
      }

      {:ok, parsed} = SamplingClient.parse_sample_response(response)

      assert parsed.prompt_logprobs == [0.1, 0.2, 0.3]
    end
  end

  describe "create_async/2" do
    defmodule MockServiceAPI do
      def create_sampling_session(_config, request) do
        seq_id = request.sampling_session_seq_id || 1
        {:ok, %{"sampling_session_id" => "sampling-async-#{seq_id}"}}
      end
    end

    test "returns a Task that creates a SamplingClient", %{config: config} do
      # Create a mock service client
      service_client = %Tinkex.ServiceClient{
        session_id: "session-123",
        config: config,
        service_api: MockServiceAPI,
        training_counter: :atomics.new(1, []),
        sampling_counter: :atomics.new(1, [])
      }

      task = SamplingClient.create_async(service_client, base_model: "test-model")

      assert %Task{} = task
      {:ok, sampling_client} = Task.await(task)
      assert %SamplingClient{} = sampling_client
      assert String.starts_with?(sampling_client.sampling_session_id, "sampling-async-")
    end

    test "passes options through to create_sampling_client", %{config: config} do
      service_client = %Tinkex.ServiceClient{
        session_id: "session-456",
        config: config,
        service_api: MockServiceAPI,
        training_counter: :atomics.new(1, []),
        sampling_counter: :atomics.new(1, [])
      }

      task = SamplingClient.create_async(service_client, model_path: "tinker://test/path")

      {:ok, sampling_client} = Task.await(task)
      assert %SamplingClient{} = sampling_client
      assert sampling_client.config == config
    end
  end
end
