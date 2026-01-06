defmodule Tinkex.Training.CustomLossTest do
  use ExUnit.Case, async: true

  alias Tinkex.Training.CustomLoss
  alias Tinkex.Types.{Datum, ForwardBackwardOutput, TensorData}

  describe "extract_per_datum_logprobs/1" do
    test "preserves per-datum structure from forward output" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: "cross_entropy",
        loss_fn_outputs: [
          %{"logprobs" => %{"data" => [-1.0, -2.0], "dtype" => "float32"}},
          %{"logprobs" => %{"data" => [-0.5, -1.5, -2.5], "dtype" => "float32"}},
          %{"logprobs" => %{"data" => [-3.0], "dtype" => "float32"}}
        ],
        metrics: %{"loss" => 1.5}
      }

      {:ok, logprobs_list} = CustomLoss.extract_per_datum_logprobs(output)

      assert length(logprobs_list) == 3
      assert Nx.shape(Enum.at(logprobs_list, 0)) == {2}
      assert Nx.shape(Enum.at(logprobs_list, 1)) == {3}
      assert Nx.shape(Enum.at(logprobs_list, 2)) == {1}
    end

    test "handles list of outputs (chunked)" do
      outputs = [
        %ForwardBackwardOutput{
          loss_fn_output_type: "cross_entropy",
          loss_fn_outputs: [
            %{"logprobs" => %{"data" => [-1.0], "dtype" => "float32"}}
          ],
          metrics: %{}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: "cross_entropy",
          loss_fn_outputs: [
            %{"logprobs" => %{"data" => [-2.0], "dtype" => "float32"}}
          ],
          metrics: %{}
        }
      ]

      {:ok, logprobs_list} = CustomLoss.extract_per_datum_logprobs(outputs)

      assert length(logprobs_list) == 2
    end

    test "handles TensorData logprobs" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: "cross_entropy",
        loss_fn_outputs: [
          %{"logprobs" => %TensorData{data: [-1.0, -2.0], dtype: :float32, shape: [2]}}
        ],
        metrics: %{}
      }

      {:ok, logprobs_list} = CustomLoss.extract_per_datum_logprobs(output)

      assert length(logprobs_list) == 1
      assert Nx.shape(hd(logprobs_list)) == {2}
    end

    test "handles raw list logprobs" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: "cross_entropy",
        loss_fn_outputs: [
          %{"logprobs" => [-1.0, -2.0]}
        ],
        metrics: %{}
      }

      {:ok, logprobs_list} = CustomLoss.extract_per_datum_logprobs(output)

      assert length(logprobs_list) == 1
    end

    test "returns error for invalid input" do
      {:error, {:invalid_forward_output, _}} = CustomLoss.extract_per_datum_logprobs(:invalid)
    end

    test "returns error for missing logprobs" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: "cross_entropy",
        loss_fn_outputs: [%{"not_logprobs" => [-1.0]}],
        metrics: %{}
      }

      {:error, {:invalid_logprobs, _}} = CustomLoss.extract_per_datum_logprobs(output)
    end
  end

  describe "compute_gradients/3" do
    test "computes gradients for each logprobs tensor" do
      logprobs_list = [
        Nx.tensor([-1.0, -2.0]),
        Nx.tensor([-0.5, -1.5])
      ]

      loss_fn = fn _data, logprobs ->
        total = logprobs |> Enum.map(&Nx.sum/1) |> Enum.reduce(&Nx.add/2)
        {total, %{"custom" => 1.0}}
      end

      {:ok, {gradients, metrics}} = CustomLoss.compute_gradients([], logprobs_list, loss_fn)

      assert length(gradients) == 2
      assert Nx.to_flat_list(Enum.at(gradients, 0)) == [1.0, 1.0]
      assert metrics == %{"custom" => 1.0}
    end

    test "returns empty list for empty input" do
      {:ok, {gradients, metrics}} = CustomLoss.compute_gradients([], [], fn _, _ -> {0, %{}} end)

      assert gradients == []
      assert metrics == %{}
    end

    test "handles complex loss functions" do
      logprobs = [Nx.tensor([-1.0, -2.0, -3.0])]

      loss_fn = fn _data, [lp] ->
        loss = Nx.sum(Nx.multiply(lp, Nx.tensor([1.0, 2.0, 3.0])))
        {loss, %{"weighted" => true}}
      end

      {:ok, {[grad], metrics}} = CustomLoss.compute_gradients([], logprobs, loss_fn)

      # Gradient should be [1.0, 2.0, 3.0] (coefficients)
      assert Nx.to_flat_list(grad) == [1.0, 2.0, 3.0]
      assert metrics == %{"weighted" => true}
    end
  end

  describe "build_linear_loss_data/2" do
    test "creates synthetic data with negative gradients as weights" do
      original_data = [
        %Datum{
          model_input: %{chunks: [%{data: [1, 2, 3]}]},
          loss_fn_inputs: %{"target_tokens" => %TensorData{data: [4, 5, 6], dtype: :int64}}
        }
      ]

      gradients = [Nx.tensor([0.1, 0.2, 0.3])]

      linear_data = CustomLoss.build_linear_loss_data(original_data, gradients)

      assert length(linear_data) == 1
      datum = hd(linear_data)

      assert datum.model_input == hd(original_data).model_input

      assert datum.loss_fn_inputs["target_tokens"] ==
               hd(original_data).loss_fn_inputs["target_tokens"]

      weights = datum.loss_fn_inputs["weights"]

      assert Enum.zip(weights.data, [-0.1, -0.2, -0.3])
             |> Enum.all?(fn {got, expected} -> abs(got - expected) < 1.0e-6 end)
    end

    test "handles multiple datums" do
      original_data = [
        %Datum{
          model_input: %{chunks: [%{data: [1]}]},
          loss_fn_inputs: %{"target_tokens" => %TensorData{data: [1], dtype: :int64}}
        },
        %Datum{
          model_input: %{chunks: [%{data: [2]}]},
          loss_fn_inputs: %{"target_tokens" => %TensorData{data: [2], dtype: :int64}}
        }
      ]

      gradients = [Nx.tensor([0.5]), Nx.tensor([0.7])]

      linear_data = CustomLoss.build_linear_loss_data(original_data, gradients)

      assert length(linear_data) == 2
    end

    test "raises for missing target_tokens" do
      original_data = [
        %Datum{
          model_input: %{chunks: [%{data: [1]}]},
          loss_fn_inputs: %{}
        }
      ]

      gradients = [Nx.tensor([0.1])]

      assert_raise ArgumentError, ~r/target_tokens missing/, fn ->
        CustomLoss.build_linear_loss_data(original_data, gradients)
      end
    end

    test "handles atom keys for target_tokens" do
      original_data = [
        %Datum{
          model_input: %{chunks: [%{data: [1]}]},
          loss_fn_inputs: %{target_tokens: %TensorData{data: [1], dtype: :int64}}
        }
      ]

      gradients = [Nx.tensor([0.1])]

      linear_data = CustomLoss.build_linear_loss_data(original_data, gradients)

      assert length(linear_data) == 1
    end
  end
end
