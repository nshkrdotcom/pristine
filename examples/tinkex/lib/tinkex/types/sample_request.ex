defmodule Tinkex.Types.SampleRequest do
  @moduledoc """
  Request for text generation/sampling.

  Mirrors Python `tinker.types.SampleRequest`.

  ## Fields

  - `sampling_session_id` - Sampling session ID (mutually exclusive with base_model/model_path)
  - `seq_id` - Sequence ID for request ordering
  - `base_model` - Base model for new session (mutually exclusive with sampling_session_id)
  - `model_path` - Tinker path to weights (mutually exclusive with sampling_session_id)
  - `prompt` - Model input tokens
  - `sampling_params` - Sampling parameters (temperature, max_tokens, etc.)
  - `num_samples` - Number of samples to generate (default: 1)
  - `prompt_logprobs` - Whether to return prompt logprobs (tri-state: true/false/nil)
  - `topk_prompt_logprobs` - Number of top-k logprobs per prompt token
  - `type` - Request type, always "sample"

  ## Prompt Logprobs

  The `prompt_logprobs` field is tri-state:
  - `true` - Return prompt logprobs
  - `false` - Do not return prompt logprobs
  - `nil` - Omit from request (server decides)
  """

  alias Tinkex.Types.{ModelInput, SamplingParams}

  @enforce_keys [:prompt, :sampling_params]
  defstruct [
    :sampling_session_id,
    :seq_id,
    :base_model,
    :model_path,
    :prompt,
    :sampling_params,
    num_samples: 1,
    prompt_logprobs: nil,
    topk_prompt_logprobs: 0,
    type: "sample"
  ]

  @type t :: %__MODULE__{
          sampling_session_id: String.t() | nil,
          seq_id: integer() | nil,
          base_model: String.t() | nil,
          model_path: String.t() | nil,
          prompt: ModelInput.t() | [integer()],
          sampling_params: SamplingParams.t() | map(),
          num_samples: pos_integer(),
          prompt_logprobs: boolean() | nil,
          topk_prompt_logprobs: non_neg_integer(),
          type: String.t()
        }

  defimpl Jason.Encoder do
    def encode(request, opts) do
      map =
        %{
          "prompt" => encode_prompt(request.prompt),
          "sampling_params" => encode_sampling_params(request.sampling_params),
          "num_samples" => request.num_samples,
          "topk_prompt_logprobs" => request.topk_prompt_logprobs,
          "type" => request.type
        }
        |> maybe_put("sampling_session_id", request.sampling_session_id)
        |> maybe_put("seq_id", request.seq_id)
        |> maybe_put("base_model", request.base_model)
        |> maybe_put("model_path", request.model_path)
        |> maybe_put_prompt_logprobs(request.prompt_logprobs)

      Jason.Encode.map(map, opts)
    end

    defp encode_prompt(%ModelInput{} = input) do
      ModelInput.to_ints(input)
    end

    defp encode_prompt(tokens) when is_list(tokens), do: tokens

    defp encode_sampling_params(%SamplingParams{} = params) do
      params
      |> Map.from_struct()
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end

    defp encode_sampling_params(params) when is_map(params), do: params

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)

    # Only include prompt_logprobs if it's explicitly true or false
    defp maybe_put_prompt_logprobs(map, nil), do: map

    defp maybe_put_prompt_logprobs(map, value) when is_boolean(value) do
      Map.put(map, "prompt_logprobs", value)
    end
  end
end
