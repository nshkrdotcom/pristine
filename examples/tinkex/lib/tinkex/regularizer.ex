defmodule Tinkex.Regularizer do
  @moduledoc """
  Behaviour for implementing regularizers.

  Regularizers can be implemented as:
  1. Anonymous functions matching the callback spec
  2. Modules implementing this behaviour
  3. Tasks for async operations

  ## Implementing a Regularizer Module

      defmodule MyRegularizers.L1Sparsity do
        @behaviour Tinkex.Regularizer

        @impl true
        def compute(_data, logprobs, _opts) do
          # Compute L1 norm
          l1 = compute_l1(logprobs)
          {l1, %{"l1_value" => l1}}
        end

        @impl true
        def name, do: "l1_sparsity"
      end

  ## Using as Anonymous Function

      regularizer_spec = %RegularizerSpec{
        fn: fn _data, logprobs ->
          {compute_sum(logprobs), %{}}
        end,
        weight: 0.01,
        name: "l1"
      }

  ## Using with RegularizerSpec

  Regularizers are typically used via `RegularizerSpec` structs passed to
  the regularizer pipeline:

      %RegularizerSpec{
        fn: &MyRegularizers.L1Sparsity.compute/3,
        weight: 0.01,
        name: MyRegularizers.L1Sparsity.name()
      }

  ## Note on Tensor Support

  This implementation is tensor-library agnostic. When using with Nx tensors,
  the callback functions should handle tensor operations directly. Without Nx,
  plain Elixir lists or other data structures can be used.
  """

  alias Tinkex.Types.Datum

  @doc """
  Compute the regularizer loss and metrics.

  ## Parameters
  - data: List of training Datum structs
  - logprobs: Tensor or list of log probabilities from forward pass
  - opts: Optional keyword configuration

  ## Returns
  Tuple of `{loss, metrics_map}` where:
  - loss: Scalar value representing the regularizer loss
  - metrics_map: Map of string keys to numeric values for telemetry
  """
  @callback compute(
              data :: list(Datum.t()),
              logprobs :: any(),
              opts :: keyword()
            ) :: {number() | any(), %{String.t() => number()}}

  @doc """
  Return the regularizer name for telemetry and logging.

  This callback is optional. If not implemented, the name should be
  provided via the RegularizerSpec.
  """
  @callback name() :: String.t()

  @optional_callbacks [name: 0]

  @doc """
  Execute a regularizer (function or module) and return results.

  Handles both anonymous functions and behaviour-implementing modules.

  ## Parameters

  - `fn_or_module` - Either a function or a module implementing the behaviour
  - `data` - List of training Datum structs
  - `logprobs` - Tensor or list of log probabilities
  - `opts` - Optional keyword configuration

  ## Returns

  Tuple of `{loss, metrics_map}`

  ## Examples

      # With anonymous function (arity 2)
      Regularizer.execute(
        fn _data, logprobs -> {Enum.sum(logprobs), %{}} end,
        data,
        logprobs
      )

      # With arity-3 function and options
      Regularizer.execute(
        fn _data, logprobs, opts ->
          scale = Keyword.get(opts, :scale, 1.0)
          {Enum.sum(logprobs) * scale, %{}}
        end,
        data,
        logprobs,
        scale: 2.0
      )

      # With module
      Regularizer.execute(MyRegularizer, data, logprobs, timeout: 5000)
  """
  @spec execute(
          fn_or_module :: function() | module(),
          data :: list(Datum.t()),
          logprobs :: any(),
          opts :: keyword()
        ) :: {any(), %{String.t() => number()}}
  def execute(fn_or_module, data, logprobs, opts \\ [])

  def execute(fun, data, logprobs, _opts) when is_function(fun, 2) do
    fun.(data, logprobs)
  end

  def execute(fun, data, logprobs, opts) when is_function(fun, 3) do
    fun.(data, logprobs, opts)
  end

  def execute(module, data, logprobs, opts) when is_atom(module) do
    module.compute(data, logprobs, opts)
  end
end
