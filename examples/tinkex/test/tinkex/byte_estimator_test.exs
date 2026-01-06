defmodule Tinkex.ByteEstimatorTest do
  use ExUnit.Case, async: true

  alias Tinkex.ByteEstimator

  alias Tinkex.Types.{
    Datum,
    EncodedTextChunk,
    ImageAssetPointerChunk,
    ImageChunk,
    ModelInput,
    TensorData
  }

  describe "estimate_chunk_bytes/1" do
    test "estimates ImageChunk by data byte size" do
      chunk = %ImageChunk{
        data: "base64encodeddata",
        format: "png",
        expected_tokens: 100
      }

      assert ByteEstimator.estimate_chunk_bytes(chunk) == byte_size("base64encodeddata")
    end

    test "estimates ImageAssetPointerChunk by location byte size" do
      chunk = %ImageAssetPointerChunk{
        location: "s3://bucket/path/to/image.png",
        format: "png",
        expected_tokens: 100
      }

      assert ByteEstimator.estimate_chunk_bytes(chunk) ==
               byte_size("s3://bucket/path/to/image.png")
    end

    test "estimates EncodedTextChunk by token count * 10" do
      chunk = %EncodedTextChunk{
        tokens: [1, 2, 3, 4, 5],
        type: "EncodedTextChunk"
      }

      # 5 tokens * 10 bytes per token = 50
      assert ByteEstimator.estimate_chunk_bytes(chunk) == 50
    end

    test "returns 0 for unknown chunk types" do
      assert ByteEstimator.estimate_chunk_bytes(%{unknown: :chunk}) == 0
      assert ByteEstimator.estimate_chunk_bytes(nil) == 0
      assert ByteEstimator.estimate_chunk_bytes("string") == 0
    end
  end

  describe "estimate_model_input_bytes/1" do
    test "sums chunk estimates for ModelInput" do
      model_input = ModelInput.from_ints([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
      # 10 tokens * 10 bytes = 100
      assert ByteEstimator.estimate_model_input_bytes(model_input) == 100
    end

    test "handles empty ModelInput" do
      model_input = ModelInput.empty()
      assert ByteEstimator.estimate_model_input_bytes(model_input) == 0
    end

    test "returns 0 for non-ModelInput" do
      assert ByteEstimator.estimate_model_input_bytes(nil) == 0
      assert ByteEstimator.estimate_model_input_bytes(%{}) == 0
      assert ByteEstimator.estimate_model_input_bytes("string") == 0
    end
  end

  describe "estimate_loss_fn_inputs_bytes/1" do
    test "estimates TensorData by element count * 10" do
      loss_fn_inputs = %{
        "target" => %TensorData{data: [1, 2, 3, 4, 5], dtype: :float32, shape: [5]}
      }

      # 5 elements * 10 bytes = 50
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(loss_fn_inputs) == 50
    end

    test "estimates map with data key" do
      loss_fn_inputs = %{
        "target" => %{data: [1, 2, 3]}
      }

      # 3 elements * 10 bytes = 30
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(loss_fn_inputs) == 30
    end

    test "estimates map with string data key" do
      loss_fn_inputs = %{
        "target" => %{"data" => [1, 2, 3, 4]}
      }

      # 4 elements * 10 bytes = 40
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(loss_fn_inputs) == 40
    end

    test "sums multiple inputs" do
      loss_fn_inputs = %{
        "target1" => %TensorData{data: [1, 2, 3], dtype: :float32, shape: [3]},
        "target2" => %TensorData{data: [4, 5], dtype: :float32, shape: [2]}
      }

      # 3 * 10 + 2 * 10 = 50
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(loss_fn_inputs) == 50
    end

    test "returns 0 for non-map" do
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(nil) == 0
      assert ByteEstimator.estimate_loss_fn_inputs_bytes([]) == 0
    end
  end

  describe "estimate_datum_bytes/1" do
    test "combines model_input and loss_fn_inputs estimates" do
      model_input = ModelInput.from_ints([1, 2, 3, 4, 5])
      loss_fn_inputs = %{"target" => %TensorData{data: [1, 2, 3], dtype: :float32, shape: [3]}}

      datum = Datum.new(%{model_input: model_input, loss_fn_inputs: loss_fn_inputs})

      # 5 tokens * 10 + 3 elements * 10 = 80
      assert ByteEstimator.estimate_datum_bytes(datum) == 80
    end

    test "handles datum as map" do
      model_input = ModelInput.from_ints([1, 2])
      loss_fn_inputs = %{"target" => %{data: [1]}}

      datum = %{model_input: model_input, loss_fn_inputs: loss_fn_inputs}

      # 2 tokens * 10 + 1 element * 10 = 30
      assert ByteEstimator.estimate_datum_bytes(datum) == 30
    end

    test "returns 0 for invalid datum" do
      assert ByteEstimator.estimate_datum_bytes(nil) == 0
      assert ByteEstimator.estimate_datum_bytes(%{}) == 0
    end
  end

  describe "estimate_data_bytes/1" do
    test "sums byte estimates for list of datums" do
      model_input1 = ModelInput.from_ints([1, 2, 3])
      model_input2 = ModelInput.from_ints([4, 5])

      data = [
        Datum.new(%{model_input: model_input1, loss_fn_inputs: %{}}),
        Datum.new(%{model_input: model_input2, loss_fn_inputs: %{}})
      ]

      # 3 * 10 + 2 * 10 = 50
      assert ByteEstimator.estimate_data_bytes(data) == 50
    end

    test "handles empty list" do
      assert ByteEstimator.estimate_data_bytes([]) == 0
    end
  end
end
