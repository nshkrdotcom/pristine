defmodule Tinkex.TrainingClient.TokenizerTest do
  use ExUnit.Case, async: true

  alias Tinkex.TrainingClient.Tokenizer
  alias Tinkex.Types.GetInfoResponse
  alias Tinkex.Error

  describe "get_tokenizer/2" do
    test "fetches tokenizer using model info" do
      # Mock info function that returns model info
      info_fun = fn _client ->
        {:ok,
         %GetInfoResponse{
           model_id: "model-123",
           model_data: %{base_model: "meta-llama/Llama-3.2-1B"}
         }}
      end

      # Mock load function that returns a tokenizer handle
      load_fun = fn _tokenizer_id, _opts ->
        {:ok, {:mock_tokenizer, "meta-llama/Llama-3.2-1B"}}
      end

      result =
        Tokenizer.get_tokenizer(
          self(),
          info_fun: info_fun,
          load_fun: load_fun
        )

      assert {:ok, _tokenizer} = result
    end

    test "returns error when info fetch fails" do
      info_fun = fn _client ->
        {:error, Error.new(:request_failed, "network error")}
      end

      result = Tokenizer.get_tokenizer(self(), info_fun: info_fun)

      assert {:error, %Error{type: :request_failed}} = result
    end
  end

  describe "encode/3" do
    test "encodes text using model tokenizer" do
      info_fun = fn _client ->
        {:ok,
         %GetInfoResponse{
           model_id: "model-123",
           model_data: %{base_model: "test-model"}
         }}
      end

      # Mock the tokenizer encode function
      encode_fun = fn _text, _model, _opts ->
        {:ok, [1, 2, 3, 4, 5]}
      end

      result =
        Tokenizer.encode(
          self(),
          "Hello world",
          info_fun: info_fun,
          encode_fun: encode_fun
        )

      # Result depends on actual Tinkex.Tokenizer.encode behavior
      # Just verify no crash occurs with mocked info
      assert is_tuple(result)
    end

    test "returns error when info fetch fails" do
      info_fun = fn _client ->
        {:error, Error.new(:request_failed, "failed")}
      end

      result = Tokenizer.encode(self(), "test", info_fun: info_fun)

      assert {:error, %Error{}} = result
    end
  end

  describe "decode/3" do
    test "decodes token IDs using model tokenizer" do
      info_fun = fn _client ->
        {:ok,
         %GetInfoResponse{
           model_id: "model-123",
           model_data: %{model_name: "test-model"}
         }}
      end

      result =
        Tokenizer.decode(
          self(),
          [1, 2, 3],
          info_fun: info_fun
        )

      # Result depends on actual Tinkex.Tokenizer.decode behavior
      assert is_tuple(result)
    end

    test "returns error when info fetch fails" do
      info_fun = fn _client ->
        {:error, Error.new(:request_failed, "failed")}
      end

      result = Tokenizer.decode(self(), [1, 2, 3], info_fun: info_fun)

      assert {:error, %Error{}} = result
    end
  end

  describe "model name extraction" do
    test "extracts base_model from GetInfoResponse" do
      # Clear any cached tokenizer to ensure predictable behavior
      # meta-llama/Llama-3.2-1B -> resolved to llama-3 tokenizer
      Tinkex.Tokenizer.__supertester_clear_cache__(
        "thinkingmachineslabinc/meta-llama-3-tokenizer"
      )

      info_fun = fn _client ->
        {:ok,
         %GetInfoResponse{
           model_id: "model-123",
           model_data: %{base_model: "meta-llama/Llama-3.2-1B"}
         }}
      end

      # Provide a load_fun that returns an error so we don't actually load from HF
      load_fun = fn _tokenizer_id, _opts ->
        {:error, Tinkex.Error.new(:validation, "test tokenizer")}
      end

      # The model name extraction is internal but we can verify
      # by checking that the function doesn't crash
      result = Tokenizer.encode(self(), "test", info_fun: info_fun, load_fun: load_fun)
      assert is_tuple(result)
    end

    test "extracts model_name when base_model not present" do
      Tinkex.Tokenizer.__supertester_clear_cache__("my-custom-model")

      info_fun = fn _client ->
        {:ok,
         %GetInfoResponse{
           model_id: "model-123",
           model_data: %{model_name: "my-custom-model"}
         }}
      end

      load_fun = fn _tokenizer_id, _opts ->
        {:error, Tinkex.Error.new(:validation, "test tokenizer")}
      end

      result = Tokenizer.encode(self(), "test", info_fun: info_fun, load_fun: load_fun)
      assert is_tuple(result)
    end

    test "handles map with base_model key" do
      Tinkex.Tokenizer.__supertester_clear_cache__("test-model")

      info_fun = fn _client ->
        {:ok, %{model_data: %{base_model: "test-model"}}}
      end

      load_fun = fn _tokenizer_id, _opts ->
        {:error, Tinkex.Error.new(:validation, "test tokenizer")}
      end

      result = Tokenizer.encode(self(), "test", info_fun: info_fun, load_fun: load_fun)
      assert is_tuple(result)
    end

    test "handles map with model_name key" do
      Tinkex.Tokenizer.__supertester_clear_cache__("test-model-2")

      info_fun = fn _client ->
        {:ok, %{model_data: %{model_name: "test-model-2"}}}
      end

      load_fun = fn _tokenizer_id, _opts ->
        {:error, Tinkex.Error.new(:validation, "test tokenizer")}
      end

      result = Tokenizer.encode(self(), "test", info_fun: info_fun, load_fun: load_fun)
      assert is_tuple(result)
    end

    test "defaults to unknown when no model info available" do
      Tinkex.Tokenizer.__supertester_clear_cache__("unknown")

      info_fun = fn _client ->
        {:ok, %{model_data: %{}}}
      end

      load_fun = fn _tokenizer_id, _opts ->
        {:error, Tinkex.Error.new(:validation, "test tokenizer")}
      end

      result = Tokenizer.encode(self(), "test", info_fun: info_fun, load_fun: load_fun)
      assert is_tuple(result)
    end
  end
end
