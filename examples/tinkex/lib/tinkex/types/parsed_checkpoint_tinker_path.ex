defmodule Tinkex.Types.ParsedCheckpointTinkerPath do
  @moduledoc """
  Parsed components of a tinker:// checkpoint path.

  Parses paths like `tinker://run_id/type/checkpoint_id` into components.
  """

  @enforce_keys [:tinker_path, :training_run_id, :checkpoint_type, :checkpoint_id]
  defstruct [:tinker_path, :training_run_id, :checkpoint_type, :checkpoint_id]

  @type checkpoint_type :: String.t()

  @type t :: %__MODULE__{
          tinker_path: String.t(),
          training_run_id: String.t(),
          checkpoint_type: checkpoint_type(),
          checkpoint_id: String.t()
        }

  @doc """
  Parse a tinker path into components.

  Expected format: `tinker://run_id/type/checkpoint_id`

  ## Examples

      iex> ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/weights/ckpt-001")
      {:ok, %ParsedCheckpointTinkerPath{
        tinker_path: "tinker://run-123/weights/ckpt-001",
        training_run_id: "run-123",
        checkpoint_type: "training",
        checkpoint_id: "ckpt-001"
      }}

      iex> ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/sampler_weights/ckpt-001")
      {:ok, %ParsedCheckpointTinkerPath{
        tinker_path: "tinker://run-123/sampler_weights/ckpt-001",
        training_run_id: "run-123",
        checkpoint_type: "sampler",
        checkpoint_id: "ckpt-001"
      }}

      iex> ParsedCheckpointTinkerPath.from_tinker_path("invalid")
      {:error, %{type: :validation_error, message: "Invalid tinker path format: invalid"}}
  """
  @spec from_tinker_path(String.t()) :: {:ok, t()} | {:error, map()}
  def from_tinker_path("tinker://" <> rest = tinker_path) do
    case String.split(rest, "/") do
      [run_id, type_string, checkpoint_id]
      when run_id != "" and type_string != "" and checkpoint_id != "" ->
        case parse_checkpoint_type(type_string) do
          {:ok, checkpoint_type} ->
            {:ok,
             %__MODULE__{
               tinker_path: tinker_path,
               training_run_id: run_id,
               checkpoint_type: checkpoint_type,
               checkpoint_id: checkpoint_id
             }}

          :error ->
            invalid_path_error(tinker_path)
        end

      _ ->
        invalid_path_error(tinker_path)
    end
  end

  def from_tinker_path(tinker_path), do: invalid_path_error(tinker_path)

  @doc """
  Convert parsed checkpoint to REST path segment.

  ## Examples

      iex> parsed = %ParsedCheckpointTinkerPath{checkpoint_type: "training", checkpoint_id: "ckpt-001", ...}
      iex> ParsedCheckpointTinkerPath.checkpoint_segment(parsed)
      "weights/ckpt-001"

      iex> parsed = %ParsedCheckpointTinkerPath{checkpoint_type: "sampler", checkpoint_id: "ckpt-001", ...}
      iex> ParsedCheckpointTinkerPath.checkpoint_segment(parsed)
      "sampler_weights/ckpt-001"
  """
  @spec checkpoint_segment(t()) :: String.t()
  def checkpoint_segment(%__MODULE__{checkpoint_type: "training", checkpoint_id: id}) do
    "weights/#{id}"
  end

  def checkpoint_segment(%__MODULE__{checkpoint_type: "sampler", checkpoint_id: id}) do
    "sampler_weights/#{id}"
  end

  defp parse_checkpoint_type("weights"), do: {:ok, "training"}
  defp parse_checkpoint_type("sampler_weights"), do: {:ok, "sampler"}
  defp parse_checkpoint_type(_), do: :error

  defp invalid_path_error(tinker_path) do
    {:error, %{type: :validation_error, message: "Invalid tinker path format: #{tinker_path}"}}
  end
end
