defmodule Tinkex.Future.CombinerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tinkex.Future.Combiner
  alias Tinkex.Types.ForwardBackwardOutput

  describe "combine_forward_backward_results/1" do
    test "raises for empty list" do
      assert_raise ArgumentError, ~r/expected at least one/, fn ->
        Combiner.combine_forward_backward_results([])
      end
    end

    test "returns single result unchanged" do
      result = %ForwardBackwardOutput{
        loss_fn_output_type: :scalar,
        loss_fn_outputs: [1.0, 2.0],
        metrics: %{"loss:mean" => 1.5}
      }

      combined = Combiner.combine_forward_backward_results([result])

      assert combined.loss_fn_output_type == :scalar
      assert combined.loss_fn_outputs == [1.0, 2.0]
      assert combined.metrics == %{"loss:mean" => 1.5}
    end

    test "flattens loss_fn_outputs from multiple results" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0, 2.0],
          metrics: %{}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [3.0, 4.0],
          metrics: %{}
        }
      ]

      combined = Combiner.combine_forward_backward_results(results)
      assert combined.loss_fn_outputs == [1.0, 2.0, 3.0, 4.0]
    end

    test "takes loss_fn_output_type from first result" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [2.0],
          metrics: %{}
        }
      ]

      combined = Combiner.combine_forward_backward_results(results)
      assert combined.loss_fn_output_type == :scalar
    end

    test "logs warning for mismatched loss_fn_output_type" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :tensor,
          loss_fn_outputs: [2.0],
          metrics: %{}
        }
      ]

      log =
        capture_log(fn ->
          combined = Combiner.combine_forward_backward_results(results)
          # First type wins
          assert combined.loss_fn_output_type == :scalar
        end)

      assert log =~ "mixed loss_fn_output_type"
    end

    test "reduces metrics using MetricsReduction" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0, 2.0],
          metrics: %{"loss:sum" => 10}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [3.0],
          metrics: %{"loss:sum" => 20}
        }
      ]

      combined = Combiner.combine_forward_backward_results(results)
      assert combined.metrics["loss:sum"] == 30
    end

    test "handles nil loss_fn_outputs" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: nil,
          metrics: %{}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{}
        }
      ]

      combined = Combiner.combine_forward_backward_results(results)
      assert combined.loss_fn_outputs == [1.0]
    end
  end
end
