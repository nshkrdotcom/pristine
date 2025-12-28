defmodule Pristine.Adapters.Retry.Foundation do
  @moduledoc """
  Retry adapter backed by foundation retry policies.
  """

  @behaviour Pristine.Ports.Retry

  alias Foundation.Retry

  @impl true
  def with_retry(fun, opts) when is_function(fun, 0) do
    policy = normalize_policy(opts)
    {result, _state} = Retry.run(fun, policy)
    result
  end

  defp normalize_policy(%Retry.Policy{} = policy), do: policy
  defp normalize_policy(opts) when is_list(opts), do: Retry.Policy.new(opts)
  defp normalize_policy(_), do: Retry.Policy.new()
end
