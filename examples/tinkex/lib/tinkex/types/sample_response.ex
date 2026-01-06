defmodule Tinkex.Types.SampleResponse do
  @moduledoc """
  Response from text generation/sampling.

  Mirrors Python `tinker.types.SampleResponse`.

  ## Fields

  - `sequences` - List of generated token sequences
  - `prompt_logprobs` - Log probabilities for prompt tokens (if requested)
  - `topk_prompt_logprobs` - Top-k logprobs per prompt token (if requested)
  - `type` - Response type, always "sample"

  ## Top-K Prompt Logprobs Format

  When `topk_prompt_logprobs` is present, it contains for each prompt token
  a list of `{token_id, logprob}` tuples representing the top-k most likely
  tokens at that position.
  """

  alias Tinkex.Types.SampledSequence

  @enforce_keys [:sequences]
  defstruct [:sequences, :prompt_logprobs, :topk_prompt_logprobs, type: "sample"]

  @typedoc "A top-k entry: {token_id, logprob}"
  @type topk_entry :: {integer(), float()}

  @typedoc "Top-k logprobs per prompt token position"
  @type topk_prompt_logprobs :: [nil | [topk_entry()]] | nil

  @type t :: %__MODULE__{
          sequences: [SampledSequence.t()],
          prompt_logprobs: [float() | nil] | nil,
          topk_prompt_logprobs: topk_prompt_logprobs(),
          type: String.t()
        }

  @doc """
  Parse a sample response from JSON.

  ## Parameters

  - `json` - Map from JSON response

  ## Examples

      response = SampleResponse.from_json(%{
        "sequences" => [%{"tokens" => [1, 2, 3], "stop_reason" => "length"}],
        "type" => "sample"
      })
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    sequences =
      (json["sequences"] || json[:sequences] || [])
      |> Enum.map(&SampledSequence.from_json/1)

    %__MODULE__{
      sequences: sequences,
      prompt_logprobs: json["prompt_logprobs"] || json[:prompt_logprobs],
      topk_prompt_logprobs:
        parse_topk_prompt_logprobs(json["topk_prompt_logprobs"] || json[:topk_prompt_logprobs]),
      type: json["type"] || json[:type] || "sample"
    }
  end

  # Parse top-k prompt logprobs from various formats
  defp parse_topk_prompt_logprobs(nil), do: nil

  defp parse_topk_prompt_logprobs(entries) when is_list(entries) do
    Enum.map(entries, &parse_topk_entry/1)
  end

  defp parse_topk_entry(nil), do: nil

  defp parse_topk_entry(entry) when is_list(entry) do
    Enum.map(entry, &parse_single_topk/1)
  end

  # Handle {token_id, logprob} tuple
  defp parse_single_topk({token_id, logprob}) when is_integer(token_id) and is_number(logprob) do
    {token_id, logprob}
  end

  # Handle [token_id, logprob] list
  defp parse_single_topk([token_id, logprob]) when is_integer(token_id) and is_number(logprob) do
    {token_id, logprob}
  end

  # Handle %{"token_id" => id, "logprob" => prob} map
  defp parse_single_topk(%{"token_id" => token_id, "logprob" => logprob}) do
    {token_id, logprob}
  end

  defp parse_single_topk(%{token_id: token_id, logprob: logprob}) do
    {token_id, logprob}
  end

  defp parse_single_topk(other), do: other
end
