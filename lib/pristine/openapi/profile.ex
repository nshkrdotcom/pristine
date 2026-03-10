defmodule Pristine.OpenAPI.Profile do
  @moduledoc """
  Builds `oapi_generator` profiles for code generation that targets Pristine.

  This module is intentionally small and build-time oriented. It exposes the
  minimum set of stable hooks needed for provider-specific generation:

  - `supplemental_files` for additional OpenAPI roots
  - `profile_overrides` for provider-specific generator configuration
  """

  @type option ::
          {:base_module, module()}
          | {:output_dir, String.t()}
          | {:default_client, module()}
          | {:operation_use, module()}
          | {:error_type, module() | {module(), atom()}}
          | {:processor, module()}
          | {:renderer, module()}
          | {:supplemental_files, [String.t()]}
          | {:profile_overrides, keyword()}

  @spec build([option()]) :: keyword()
  def build(opts) when is_list(opts) do
    base_module = Keyword.fetch!(opts, :base_module)
    output_dir = Keyword.fetch!(opts, :output_dir)

    defaults = [
      processor: Keyword.get(opts, :processor, OpenAPI.Processor),
      renderer: Keyword.get(opts, :renderer, Pristine.OpenAPI.Renderer),
      reader: [
        additional_files: Keyword.get(opts, :supplemental_files, [])
      ],
      output: [
        base_module: base_module,
        default_client: Keyword.get(opts, :default_client, Pristine.OpenAPI.Client),
        location: output_dir,
        operation_use: Keyword.get(opts, :operation_use, Pristine.OpenAPI.Operation),
        types: [
          error: Keyword.get(opts, :error_type, Pristine.Error)
        ]
      ]
    ]

    deep_merge(defaults, Keyword.get(opts, :profile_overrides, []))
  end

  @spec install(atom(), [option()]) :: atom()
  def install(profile, opts) when is_atom(profile) and is_list(opts) do
    Application.put_env(:oapi_generator, profile, build(opts))
    profile
  end

  defp deep_merge(left, right) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right) do
      Keyword.merge(left, right, fn _key, left_value, right_value ->
        deep_merge(left_value, right_value)
      end)
    else
      right
    end
  end

  defp deep_merge(_left, right), do: right
end
