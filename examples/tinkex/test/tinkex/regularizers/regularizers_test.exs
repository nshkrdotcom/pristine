defmodule Tinkex.Regularizers.RegularizersTest do
  @moduledoc """
  Tests for regularizer implementations.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Regularizers.{
    L1,
    L2,
    ElasticNet,
    Entropy,
    KLDivergence,
    Consistency,
    GradientPenalty,
    Orthogonality
  }

  describe "L1 regularizer" do
    test "computes L1 penalty on logprobs" do
      logprobs = Nx.tensor([1.0, -2.0, 3.0, -4.0])

      {penalty, metrics} = L1.compute([], logprobs)

      # L1 = |1| + |-2| + |3| + |-4| = 10
      assert_in_delta Nx.to_number(penalty), 10.0, 0.001
      assert metrics["l1_penalty"]
      assert metrics["mean_abs"]
    end

    test "applies lambda scaling" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {penalty, _} = L1.compute([], logprobs, lambda: 0.1)

      # L1 = 0.1 * (1 + 2 + 3) = 0.6
      assert_in_delta Nx.to_number(penalty), 0.6, 0.001
    end

    test "supports mean reduction" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0, 4.0])

      {penalty, _} = L1.compute([], logprobs, reduction: :mean)

      # mean(|1|, |2|, |3|, |4|) = 2.5
      assert_in_delta Nx.to_number(penalty), 2.5, 0.001
    end

    test "supports probs target" do
      logprobs = Nx.tensor([-1.0, -2.0])

      {penalty, _} = L1.compute([], logprobs, target: :probs)

      # probs = exp(logprobs), L1 = sum(|probs|)
      expected = :math.exp(-1.0) + :math.exp(-2.0)
      assert_in_delta Nx.to_number(penalty), expected, 0.001
    end

    test "returns name" do
      assert L1.name() == "l1_sparsity"
    end

    test "computes sparsity metric" do
      logprobs = Nx.tensor([0.0, 0.0, 0.0, 1.0])

      {_, metrics} = L1.compute([], logprobs)

      # 3 out of 4 are near-zero
      assert_in_delta metrics["sparsity"], 0.75, 0.01
    end
  end

  describe "L2 regularizer" do
    test "computes L2 penalty on logprobs" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {penalty, metrics} = L2.compute([], logprobs)

      # L2 = 1² + 2² + 3² = 14
      assert_in_delta Nx.to_number(penalty), 14.0, 0.001
      assert metrics["l2_penalty"]
      assert metrics["rms"]
    end

    test "applies lambda scaling" do
      logprobs = Nx.tensor([1.0, 2.0])

      {penalty, _} = L2.compute([], logprobs, lambda: 0.5)

      # L2 = 0.5 * (1 + 4) = 2.5
      assert_in_delta Nx.to_number(penalty), 2.5, 0.001
    end

    test "supports mean reduction" do
      logprobs = Nx.tensor([2.0, 4.0])

      {penalty, _} = L2.compute([], logprobs, reduction: :mean)

      # mean(4, 16) = 10
      assert_in_delta Nx.to_number(penalty), 10.0, 0.001
    end

    test "supports center (deviation-based L2)" do
      logprobs = Nx.tensor([3.0, 5.0])
      center = Nx.tensor([1.0, 2.0])

      {penalty, _} = L2.compute([], logprobs, center: center)

      # deviations = [2, 3], L2 = 4 + 9 = 13
      assert_in_delta Nx.to_number(penalty), 13.0, 0.001
    end

    test "supports clipping" do
      logprobs = Nx.tensor([10.0, 10.0])

      {penalty, _} = L2.compute([], logprobs, clip: 50.0)

      # L2 = 100 + 100 = 200, but clipped to 50
      assert_in_delta Nx.to_number(penalty), 50.0, 0.001
    end

    test "returns name" do
      assert L2.name() == "l2_weight_decay"
    end
  end

  describe "ElasticNet regularizer" do
    test "computes combined L1 + L2 penalty" do
      logprobs = Nx.tensor([1.0, 2.0])

      {penalty, metrics} = ElasticNet.compute([], logprobs)

      # L1 = 1 + 2 = 3, L2 = 1 + 4 = 5
      # ElasticNet = 0.5 * 3 + 0.5 * 5 = 4
      assert_in_delta Nx.to_number(penalty), 4.0, 0.001
      assert metrics["l1_component"]
      assert metrics["l2_component"]
    end

    test "with l1_ratio = 1.0 equals L1" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {elastic_penalty, _} = ElasticNet.compute([], logprobs, l1_ratio: 1.0)
      {l1_penalty, _} = L1.compute([], logprobs)

      assert_in_delta Nx.to_number(elastic_penalty), Nx.to_number(l1_penalty), 0.001
    end

    test "with l1_ratio = 0.0 equals L2" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {elastic_penalty, _} = ElasticNet.compute([], logprobs, l1_ratio: 0.0)
      {l2_penalty, _} = L2.compute([], logprobs)

      assert_in_delta Nx.to_number(elastic_penalty), Nx.to_number(l2_penalty), 0.001
    end

    test "applies lambda scaling" do
      logprobs = Nx.tensor([1.0, 2.0])

      {penalty, _} = ElasticNet.compute([], logprobs, lambda: 0.5, l1_ratio: 0.5)

      # L1 = 3, L2 = 5, combined = 4, scaled = 2
      assert_in_delta Nx.to_number(penalty), 2.0, 0.001
    end

    test "clamps invalid l1_ratio" do
      logprobs = Nx.tensor([1.0])

      # Negative should clamp to 0
      {penalty1, metrics1} = ElasticNet.compute([], logprobs, l1_ratio: -0.5)
      assert metrics1["l1_ratio"] == 0.0

      # > 1 should clamp to 1
      {penalty2, metrics2} = ElasticNet.compute([], logprobs, l1_ratio: 1.5)
      assert metrics2["l1_ratio"] == 1.0
    end

    test "returns name" do
      assert ElasticNet.name() == "elastic_net"
    end
  end

  describe "Entropy regularizer" do
    test "computes entropy in minimize mode" do
      # Uniform distribution has high entropy
      logprobs = Nx.tensor([:math.log(0.25), :math.log(0.25), :math.log(0.25), :math.log(0.25)])

      {_penalty, metrics} = Entropy.compute([], logprobs, reduction: :sum)

      # Entropy of uniform over 4 = log(4) ≈ 1.386
      assert_in_delta metrics["entropy"], 1.386, 0.01
      assert metrics["mode"] == "minimize"
    end

    test "computes entropy in maximize mode" do
      logprobs = Nx.tensor([:math.log(0.5), :math.log(0.5)])

      {minimize_penalty, _} = Entropy.compute([], logprobs, mode: :minimize)
      {maximize_penalty, _} = Entropy.compute([], logprobs, mode: :maximize)

      # Maximize mode should negate the penalty
      assert_in_delta Nx.to_number(maximize_penalty), -Nx.to_number(minimize_penalty), 0.001
    end

    test "peaked distribution has low entropy" do
      # Very peaked distribution
      logprobs = Nx.tensor([:math.log(0.99), :math.log(0.01)])

      {_, metrics} = Entropy.compute([], logprobs)

      # Low entropy for peaked distribution
      assert metrics["entropy"] < 0.1
    end

    test "applies temperature scaling" do
      logprobs = Nx.tensor([:math.log(0.5), :math.log(0.5)])

      {low_temp_penalty, _} = Entropy.compute([], logprobs, temperature: 0.5)
      {high_temp_penalty, _} = Entropy.compute([], logprobs, temperature: 2.0)

      # Temperature affects the entropy value
      refute Nx.to_number(low_temp_penalty) == Nx.to_number(high_temp_penalty)
    end

    test "returns name" do
      assert Entropy.name() == "entropy"
    end
  end

  describe "KL Divergence regularizer" do
    test "computes KL divergence with reference logprobs" do
      p_logprobs = Nx.tensor([:math.log(0.6), :math.log(0.4)])
      q_logprobs = Nx.tensor([:math.log(0.5), :math.log(0.5)])

      {kl, metrics} = KLDivergence.compute([], p_logprobs, reference_logprobs: q_logprobs)

      assert Nx.to_number(kl) > 0
      assert metrics["kl_divergence"]
      assert metrics["direction"] == "forward"
    end

    test "KL of identical distributions is zero" do
      logprobs = Nx.tensor([:math.log(0.5), :math.log(0.5)])

      {kl, _} = KLDivergence.compute([], logprobs, reference_logprobs: logprobs)

      assert_in_delta Nx.to_number(kl), 0.0, 0.001
    end

    test "supports reverse KL" do
      p_logprobs = Nx.tensor([:math.log(0.7), :math.log(0.3)])
      q_logprobs = Nx.tensor([:math.log(0.5), :math.log(0.5)])

      {forward_kl, _} =
        KLDivergence.compute([], p_logprobs, reference_logprobs: q_logprobs, direction: :forward)

      {reverse_kl, _} =
        KLDivergence.compute([], p_logprobs, reference_logprobs: q_logprobs, direction: :reverse)

      # Forward and reverse KL are generally different
      refute_in_delta Nx.to_number(forward_kl), Nx.to_number(reverse_kl), 0.001
    end

    test "supports symmetric KL" do
      p_logprobs = Nx.tensor([:math.log(0.7), :math.log(0.3)])
      q_logprobs = Nx.tensor([:math.log(0.5), :math.log(0.5)])

      {symmetric_kl, metrics} =
        KLDivergence.compute([], p_logprobs, reference_logprobs: q_logprobs, symmetric: true)

      assert metrics["symmetric"] == true

      # Symmetric KL should be average of forward and reverse
      {forward_kl, _} =
        KLDivergence.compute([], p_logprobs, reference_logprobs: q_logprobs, direction: :forward)

      {reverse_kl, _} =
        KLDivergence.compute([], p_logprobs, reference_logprobs: q_logprobs, direction: :reverse)

      expected = (Nx.to_number(forward_kl) + Nx.to_number(reverse_kl)) / 2
      assert_in_delta Nx.to_number(symmetric_kl), expected, 0.001
    end

    test "raises without reference" do
      logprobs = Nx.tensor([0.0])

      assert_raise ArgumentError, ~r/requires :reference_logprobs/, fn ->
        KLDivergence.compute([], logprobs)
      end
    end

    test "validates shape matching" do
      p_logprobs = Nx.tensor([0.0, 0.0])
      q_logprobs = Nx.tensor([0.0, 0.0, 0.0])

      assert_raise ArgumentError, ~r/Shape mismatch/, fn ->
        KLDivergence.compute([], p_logprobs, reference_logprobs: q_logprobs)
      end
    end

    test "returns name" do
      assert KLDivergence.name() == "kl_divergence"
    end
  end

  describe "Consistency regularizer" do
    test "computes MSE between logprobs and reference" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0])
      reference = Nx.tensor([1.5, 2.5, 3.5])

      {penalty, metrics} =
        Consistency.compute([], logprobs, reference_logprobs: reference)

      # MSE = mean((0.5)² + (0.5)² + (0.5)²) = 0.25
      assert_in_delta Nx.to_number(penalty), 0.25, 0.001
      assert metrics["consistency_penalty"]
    end

    test "supports MAE metric" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0])
      reference = Nx.tensor([2.0, 3.0, 4.0])

      {penalty, _} =
        Consistency.compute([], logprobs, reference_logprobs: reference, metric: :mae)

      # MAE = mean(1 + 1 + 1) = 1.0
      assert_in_delta Nx.to_number(penalty), 1.0, 0.001
    end

    test "supports cosine distance metric" do
      # Identical vectors should have cosine distance ~0
      logprobs = Nx.tensor([1.0, 0.0, 0.0])
      reference = Nx.tensor([1.0, 0.0, 0.0])

      {penalty, _} =
        Consistency.compute([], logprobs, reference_logprobs: reference, metric: :cosine)

      assert_in_delta Nx.to_number(penalty), 0.0, 0.001
    end

    test "orthogonal vectors have cosine distance 1" do
      logprobs = Nx.tensor([1.0, 0.0])
      reference = Nx.tensor([0.0, 1.0])

      {penalty, _} =
        Consistency.compute([], logprobs, reference_logprobs: reference, metric: :cosine)

      assert_in_delta Nx.to_number(penalty), 1.0, 0.001
    end

    test "identical tensors have zero penalty" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {penalty, _} = Consistency.compute([], logprobs, reference_logprobs: logprobs)

      assert_in_delta Nx.to_number(penalty), 0.0, 0.001
    end

    test "validates shape matching" do
      logprobs = Nx.tensor([1.0, 2.0])
      reference = Nx.tensor([1.0, 2.0, 3.0])

      assert_raise ArgumentError, ~r/Shape mismatch/, fn ->
        Consistency.compute([], logprobs, reference_logprobs: reference)
      end
    end

    test "returns name" do
      assert Consistency.name() == "consistency"
    end
  end

  describe "GradientPenalty regularizer" do
    test "computes gradient penalty in output mode" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0, 4.0])

      {penalty, metrics} = GradientPenalty.compute([], logprobs)

      assert is_number(Nx.to_number(penalty))
      assert metrics["gradient_penalty"]
      assert metrics["gradient_norm"]
      assert metrics["mode"] == "output"
    end

    test "computes gradient penalty in interpolated mode" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0])
      reference = Nx.tensor([2.0, 3.0, 4.0])

      {penalty, metrics} =
        GradientPenalty.compute([], logprobs,
          mode: :interpolated,
          reference_logprobs: reference
        )

      assert is_number(Nx.to_number(penalty))
      assert metrics["mode"] == "interpolated"
    end

    test "supports custom target norm" do
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {_, metrics1} = GradientPenalty.compute([], logprobs, target_norm: 1.0)
      {_, metrics2} = GradientPenalty.compute([], logprobs, target_norm: 2.0)

      assert metrics1["target_norm"] == 1.0
      assert metrics2["target_norm"] == 2.0
    end

    test "requires reference for interpolated mode" do
      logprobs = Nx.tensor([1.0, 2.0])

      assert_raise ArgumentError, ~r/requires :reference_logprobs/, fn ->
        GradientPenalty.compute([], logprobs, mode: :interpolated)
      end
    end

    test "returns name" do
      assert GradientPenalty.name() == "gradient_penalty"
    end
  end

  describe "Orthogonality regularizer" do
    test "identity matrix has near-zero penalty" do
      identity = Nx.eye(3)

      {penalty, metrics} = Orthogonality.compute([], identity)

      # Identity is already orthogonal
      assert_in_delta Nx.to_number(penalty), 0.0, 0.001
      assert metrics["orthogonality_penalty"]
    end

    test "non-orthogonal matrix has positive penalty" do
      # Create a matrix that's not orthogonal
      matrix = Nx.tensor([[1.0, 1.0], [1.0, 1.0]])

      {penalty, _} = Orthogonality.compute([], matrix)

      assert Nx.to_number(penalty) > 0
    end

    test "1D tensor with unit norm has low penalty" do
      # Unit vector
      unit_vec = Nx.tensor([1.0, 0.0, 0.0])

      {penalty, _} = Orthogonality.compute([], unit_vec)

      # Already has norm 1
      assert_in_delta Nx.to_number(penalty), 0.0, 0.001
    end

    test "1D tensor with non-unit norm has positive penalty" do
      non_unit = Nx.tensor([2.0, 0.0, 0.0])

      {penalty, _} = Orthogonality.compute([], non_unit)

      # Norm is 2, deviation from 1 is 3 (4-1=3), squared = 9
      assert Nx.to_number(penalty) > 0
    end

    test "computes frobenius norm metric" do
      tensor = Nx.tensor([[3.0, 0.0], [0.0, 4.0]])

      {_, metrics} = Orthogonality.compute([], tensor)

      # Frobenius norm = sqrt(9 + 16) = 5
      assert_in_delta metrics["tensor_norm"], 5.0, 0.001
    end

    test "returns name" do
      assert Orthogonality.name() == "orthogonality"
    end
  end

  describe "Regularizer behaviour compliance" do
    test "all regularizers implement compute/3 and name/0" do
      modules = [
        L1,
        L2,
        ElasticNet,
        Entropy,
        KLDivergence,
        Consistency,
        GradientPenalty,
        Orthogonality
      ]

      logprobs = Nx.tensor([0.0, 0.0])
      reference = Nx.tensor([0.0, 0.0])

      for module <- modules do
        # Ensure module is loaded before checking exports
        Code.ensure_loaded!(module)
        functions = module.__info__(:functions)
        assert {:compute, 3} in functions, "#{module} should export compute/3"
        assert {:name, 0} in functions, "#{module} should export name/0"
        assert is_binary(module.name())

        # Some regularizers require reference_logprobs
        opts =
          cond do
            module in [KLDivergence, Consistency] ->
              [reference_logprobs: reference]

            true ->
              []
          end

        {result, metrics} = module.compute([], logprobs, opts)
        assert is_struct(result, Nx.Tensor) or is_number(result)
        assert is_map(metrics)
      end
    end
  end
end
