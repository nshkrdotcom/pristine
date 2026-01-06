defmodule Tinkex.TrainingClient.DataProcessorTest do
  use ExUnit.Case, async: true

  alias Tinkex.TrainingClient.DataProcessor
  alias Tinkex.Types.{Datum, TensorData}

  describe "chunk_data/1" do
    test "returns empty list for empty data" do
      assert DataProcessor.chunk_data([]) == []
    end

    test "chunks small data into single chunk" do
      data = [%{id: 1}, %{id: 2}, %{id: 3}]
      chunks = DataProcessor.chunk_data(data)

      assert length(chunks) == 1
      assert hd(chunks) == data
    end

    test "chunks large data based on max chunk length" do
      # Create data larger than max_chunk_len (1024)
      data = Enum.map(1..1500, fn i -> %{id: i} end)
      chunks = DataProcessor.chunk_data(data)

      assert length(chunks) >= 2
      # Each chunk should be at most 1024 items
      Enum.each(chunks, fn chunk ->
        assert length(chunk) <= 1024
      end)
    end
  end

  describe "allocate_request_ids/2" do
    test "returns empty list for zero count" do
      assert DataProcessor.allocate_request_ids(0, 10) == {[], 10}
    end

    test "returns empty list for negative count" do
      assert DataProcessor.allocate_request_ids(-5, 10) == {[], 10}
    end

    test "allocates sequential IDs starting from counter" do
      {ids, new_counter} = DataProcessor.allocate_request_ids(3, 10)

      assert ids == [10, 11, 12]
      assert new_counter == 13
    end

    test "allocates single ID" do
      {ids, new_counter} = DataProcessor.allocate_request_ids(1, 5)

      assert ids == [5]
      assert new_counter == 6
    end
  end

  describe "fetch_target_tokens_tensor/1" do
    test "extracts Nx.Tensor from loss_fn_inputs" do
      tensor = Nx.tensor([1, 2, 3])

      datum = %Datum{
        model_input: %{},
        loss_fn_inputs: %{"target_tokens" => tensor}
      }

      assert {:ok, ^tensor} = DataProcessor.fetch_target_tokens_tensor(datum)
    end

    test "extracts TensorData from loss_fn_inputs" do
      # Create a TensorData using the from_nx helper to ensure correct format
      tensor = Nx.tensor([1, 2, 3], type: :s64)
      tensor_data = TensorData.from_nx(tensor)

      datum = %Datum{
        model_input: %{},
        loss_fn_inputs: %{"target_tokens" => tensor_data}
      }

      result = DataProcessor.fetch_target_tokens_tensor(datum)
      assert {:ok, %Nx.Tensor{}} = result
    end

    test "handles atom key for target_tokens" do
      tensor = Nx.tensor([1, 2, 3])

      datum = %Datum{
        model_input: %{},
        loss_fn_inputs: %{target_tokens: tensor}
      }

      assert {:ok, ^tensor} = DataProcessor.fetch_target_tokens_tensor(datum)
    end

    test "returns error for missing target_tokens" do
      datum = %Datum{
        model_input: %{},
        loss_fn_inputs: %{}
      }

      assert {:error, error} = DataProcessor.fetch_target_tokens_tensor(datum)
      assert error.type == :validation
      assert error.message =~ "target_tokens missing"
    end

    test "returns error for invalid target_tokens type" do
      datum = %Datum{
        model_input: %{},
        loss_fn_inputs: %{"target_tokens" => "invalid"}
      }

      assert {:error, error} = DataProcessor.fetch_target_tokens_tensor(datum)
      assert error.type == :validation
      assert error.message =~ "Invalid target_tokens"
    end
  end

  describe "build_placeholder_gradients/1" do
    test "returns empty list for empty data" do
      assert {:ok, []} = DataProcessor.build_placeholder_gradients([])
    end

    test "builds zero gradients matching tensor shape" do
      tensor = Nx.tensor([1.0, 2.0, 3.0])

      data = [
        %Datum{model_input: %{}, loss_fn_inputs: %{"target_tokens" => tensor}}
      ]

      assert {:ok, [grad]} = DataProcessor.build_placeholder_gradients(data)
      assert Nx.shape(grad) == {3}
      assert Nx.to_flat_list(grad) == [0.0, 0.0, 0.0]
    end

    test "builds gradients for multiple datums" do
      tensor1 = Nx.tensor([1.0, 2.0])
      tensor2 = Nx.tensor([1.0, 2.0, 3.0, 4.0])

      data = [
        %Datum{model_input: %{}, loss_fn_inputs: %{"target_tokens" => tensor1}},
        %Datum{model_input: %{}, loss_fn_inputs: %{"target_tokens" => tensor2}}
      ]

      assert {:ok, [grad1, grad2]} = DataProcessor.build_placeholder_gradients(data)
      assert Nx.shape(grad1) == {2}
      assert Nx.shape(grad2) == {4}
    end

    test "returns error if any datum has missing target_tokens" do
      tensor = Nx.tensor([1.0, 2.0])

      data = [
        %Datum{model_input: %{}, loss_fn_inputs: %{"target_tokens" => tensor}},
        %Datum{model_input: %{}, loss_fn_inputs: %{}}
      ]

      assert {:error, error} = DataProcessor.build_placeholder_gradients(data)
      assert error.type == :validation
    end
  end
end
