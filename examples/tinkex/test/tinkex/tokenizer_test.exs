defmodule Tinkex.TokenizerTest do
  use ExUnit.Case, async: true

  alias Tinkex.Tokenizer
  alias Tinkex.Error

  describe "get_tokenizer_id/3" do
    test "returns model_name for standard model" do
      assert Tokenizer.get_tokenizer_id("gpt2", nil) == "gpt2"
    end

    test "converts atom model_name to string" do
      assert Tokenizer.get_tokenizer_id(:gpt2, nil) == "gpt2"
    end

    test "applies Llama-3 gating workaround" do
      assert Tokenizer.get_tokenizer_id("meta-llama/Llama-3-8B", nil) ==
               "thinkingmachineslabinc/meta-llama-3-tokenizer"

      assert Tokenizer.get_tokenizer_id("meta-llama/Llama-3-70B-Instruct", nil) ==
               "thinkingmachineslabinc/meta-llama-3-tokenizer"
    end

    test "strips variant from org/model/variant format" do
      assert Tokenizer.get_tokenizer_id("org/model/variant", nil) == "org/model"
    end

    test "keeps simple model names" do
      assert Tokenizer.get_tokenizer_id("simple-model", nil) == "simple-model"
    end

    test "keeps org/model format" do
      assert Tokenizer.get_tokenizer_id("org/model", nil) == "org/model"
    end

    test "uses tokenizer_id from training_client info when available" do
      info = %{model_data: %{tokenizer_id: "custom-tokenizer-id"}}
      info_fun = fn _client -> {:ok, info} end

      assert Tokenizer.get_tokenizer_id("ignored-model", :mock_client, info_fun: info_fun) ==
               "custom-tokenizer-id"
    end

    test "falls back to heuristics when training_client info unavailable" do
      info_fun = fn _client -> {:error, :not_found} end

      assert Tokenizer.get_tokenizer_id("meta-llama/Llama-3-8B", :mock_client, info_fun: info_fun) ==
               "thinkingmachineslabinc/meta-llama-3-tokenizer"
    end

    test "falls back to heuristics when info lacks tokenizer_id" do
      info = %{model_data: %{name: "some-model"}}
      info_fun = fn _client -> {:ok, info} end

      assert Tokenizer.get_tokenizer_id("org/model", :mock_client, info_fun: info_fun) ==
               "org/model"
    end
  end

  describe "kimi_tokenizer?/1" do
    test "returns true for Kimi tokenizer ID" do
      assert Tokenizer.kimi_tokenizer?("moonshotai/Kimi-K2-Thinking")
    end

    test "returns false for other tokenizer IDs" do
      refute Tokenizer.kimi_tokenizer?("gpt2")
      refute Tokenizer.kimi_tokenizer?("meta-llama/Llama-3-8B")
    end
  end

  describe "encode/3" do
    test "returns error for non-binary text" do
      assert {:error, %Error{type: :validation}} = Tokenizer.encode(123, "model")
      assert {:error, %Error{message: msg}} = Tokenizer.encode(123, "model")
      assert msg =~ "text must be a binary"
    end

    test "returns error for non-binary model_name" do
      assert {:error, %Error{type: :validation}} = Tokenizer.encode("text", 123)
      assert {:error, %Error{message: msg}} = Tokenizer.encode("text", 123)
      assert msg =~ "model_name must be a binary"
    end

    test "encodes text with mock tokenizer" do
      # Use a mock load_fun to avoid network requests
      mock_encoding = mock_tiktoken_encoding()
      load_fun = fn _id, _opts -> {:ok, mock_encoding} end

      result = Tokenizer.encode("hello", "test-model", load_fun: load_fun)
      assert {:ok, ids} = result
      assert is_list(ids)
      assert Enum.all?(ids, &is_integer/1)
    end
  end

  describe "decode/3" do
    test "returns error for non-binary model_name" do
      assert {:error, %Error{type: :validation}} = Tokenizer.decode([1, 2, 3], 123)
      assert {:error, %Error{message: msg}} = Tokenizer.decode([1, 2, 3], 123)
      assert msg =~ "model_name must be a binary"
    end

    test "returns error for non-list ids" do
      assert {:error, %Error{type: :validation}} = Tokenizer.decode("not a list", "model")
      assert {:error, %Error{message: msg}} = Tokenizer.decode("not a list", "model")
      assert msg =~ "ids must be a list"
    end

    test "returns error for non-integer ids in list" do
      assert {:error, %Error{type: :validation}} = Tokenizer.decode([1, "two", 3], "model")
      assert {:error, %Error{message: msg}} = Tokenizer.decode([1, "two", 3], "model")
      assert msg =~ "ids must be integers"
    end

    test "decodes ids with mock tokenizer" do
      mock_encoding = mock_tiktoken_encoding()
      load_fun = fn _id, _opts -> {:ok, mock_encoding} end

      # First encode to get valid IDs
      {:ok, ids} = Tokenizer.encode("hello", "test-model", load_fun: load_fun)

      result = Tokenizer.decode(ids, "test-model", load_fun: load_fun)
      assert {:ok, text} = result
      assert is_binary(text)
    end
  end

  describe "get_or_load_tokenizer/2" do
    test "returns error for non-binary tokenizer_id" do
      assert {:error, %Error{type: :validation}} = Tokenizer.get_or_load_tokenizer(123)
      assert {:error, %Error{message: msg}} = Tokenizer.get_or_load_tokenizer(123)
      assert msg =~ "invalid tokenizer_id"
    end

    test "loads tokenizer with custom load_fun" do
      # Clear cache to ensure load_fun is called
      Tokenizer.__supertester_clear_cache__("test-model")

      mock_encoding = mock_tiktoken_encoding()
      load_fun = fn _id, _opts -> {:ok, mock_encoding} end

      {:ok, tokenizer} = Tokenizer.get_or_load_tokenizer("test-model", load_fun: load_fun)
      assert tokenizer == mock_encoding
    end

    test "caches tokenizer in ETS" do
      # Create isolated table for this test
      table = :ets.new(:test_tokenizer_cache, [:set, :public])
      Tokenizer.__supertester_set_table__(:cache_table, table)

      on_exit(fn ->
        Tokenizer.__supertester_set_table__(:cache_table, :tinkex_tokenizers)

        if :ets.info(table) != :undefined do
          :ets.delete(table)
        end
      end)

      call_count = :counters.new(1, [:atomics])

      mock_encoding = mock_tiktoken_encoding()

      load_fun = fn _id, _opts ->
        :counters.add(call_count, 1, 1)
        {:ok, mock_encoding}
      end

      # First call should load
      {:ok, _} = Tokenizer.get_or_load_tokenizer("cached-model", load_fun: load_fun)
      assert :counters.get(call_count, 1) == 1

      # Second call should use cache
      {:ok, _} = Tokenizer.get_or_load_tokenizer("cached-model", load_fun: load_fun)
      assert :counters.get(call_count, 1) == 1
    end

    test "handles load_fun error" do
      load_fun = fn _id, _opts -> {:error, "failed to load"} end

      {:error, %Error{type: :validation, message: msg}} =
        Tokenizer.get_or_load_tokenizer("failing-model", load_fun: load_fun)

      assert msg =~ "Failed to load tokenizer"
    end
  end

  describe "encode_text/3" do
    test "is alias for encode/3" do
      mock_encoding = mock_tiktoken_encoding()
      load_fun = fn _id, _opts -> {:ok, mock_encoding} end

      result1 = Tokenizer.encode("test", "model", load_fun: load_fun)
      result2 = Tokenizer.encode_text("test", "model", load_fun: load_fun)

      assert result1 == result2
    end
  end

  # Helper to create a mock TiktokenEx.Encoding struct
  defp mock_tiktoken_encoding do
    # Build a minimal encoding that can encode/decode basic ASCII
    mergeable_ranks =
      ?a..?z
      |> Enum.with_index()
      |> Enum.into(%{}, fn {char, idx} -> {<<char>>, idx} end)
      |> Map.put(" ", 26)

    {:ok, encoding} =
      TiktokenEx.Encoding.new(
        pat_str: ~S"[a-zA-Z]+|[0-9]+|\s+|.",
        mergeable_ranks: mergeable_ranks,
        special_tokens: %{}
      )

    encoding
  end
end
