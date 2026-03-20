defmodule PristineCodegen.Compiler do
  @moduledoc """
  Shared compiler entrypoint for provider definitions, plugins, generated code,
  and committed artifact verification.
  """

  alias PristineCodegen.Artifacts
  alias PristineCodegen.Compilation
  alias PristineCodegen.Normalize
  alias PristineCodegen.Provider
  alias PristineCodegen.ProviderIR
  alias PristineCodegen.Render.ElixirSDK
  alias PristineCodegen.Source.Dataset

  @spec compile(module(), keyword()) :: {:ok, Compilation.t()}
  def compile(provider_module, opts \\ []) when is_atom(provider_module) and is_list(opts) do
    paths = Provider.paths(provider_module, opts)

    provider_ir =
      provider_module
      |> Provider.definition(opts)
      |> merge_source_datasets(provider_module, opts)
      |> Normalize.from_definition()
      |> apply_provider_ir_plugins(provider_module, opts)

    rendered_files = ElixirSDK.render(provider_ir)
    provider_ir = Normalize.attach_code_artifacts(provider_ir, rendered_files)
    artifact_files = Artifacts.render(provider_ir, rendered_files)

    {:ok,
     %Compilation{
       provider_module: provider_module,
       provider_ir: provider_ir,
       rendered_files: rendered_files,
       artifact_files: artifact_files,
       paths: paths
     }}
  end

  @spec generate(module(), keyword()) :: {:ok, Compilation.t()}
  def generate(provider_module, opts \\ []) do
    with {:ok, compilation} <- compile(provider_module, opts) do
      {:ok, Artifacts.write_files(compilation)}
    end
  end

  @spec emit_ir(module(), keyword()) :: {:ok, String.t()}
  def emit_ir(provider_module, opts \\ []) do
    with {:ok, compilation} <- compile(provider_module, opts) do
      {:ok, PristineCodegen.JSON.encode!(ProviderIR.to_map(compilation.provider_ir))}
    end
  end

  @spec refresh(module(), keyword()) :: {:ok, Compilation.t()}
  def refresh(provider_module, opts \\ []) do
    _ = Provider.refresh(provider_module, opts)
    generate(provider_module, opts)
  end

  @spec verify(module(), keyword()) :: :ok | {:error, map()}
  def verify(provider_module, opts \\ []) do
    with {:ok, compilation} <- compile(provider_module, opts) do
      expected_files = Compilation.all_files(compilation)

      missing_paths = missing_paths(compilation, expected_files)
      stale_paths = stale_paths(compilation, expected_files, missing_paths)
      forbidden_paths = forbidden_paths(compilation.provider_ir, compilation.paths.project_root)

      if missing_paths == [] and stale_paths == [] and forbidden_paths == [] do
        :ok
      else
        {:error,
         %{
           missing_paths: missing_paths,
           stale_paths: stale_paths,
           forbidden_paths: forbidden_paths
         }}
      end
    end
  end

  defp merge_source_datasets(definition, provider_module, opts) do
    Enum.reduce(Provider.source_plugins(provider_module), definition, fn plugin_module, acc ->
      case plugin_module.load(provider_module, opts) do
        %Dataset{} = dataset ->
          merge_source_dataset(acc, dataset)

        other ->
          raise ArgumentError,
                "expected source plugin #{inspect(plugin_module)} to return PristineCodegen.Source.Dataset, got: #{inspect(other)}"
      end
    end)
  end

  defp apply_provider_ir_plugins(provider_ir, provider_module, opts) do
    provider_ir
    |> apply_plugins(Provider.auth_plugins(provider_module), opts, :auth)
    |> apply_plugins(Provider.pagination_plugins(provider_module), opts, :pagination)
    |> apply_plugins(Provider.docs_plugins(provider_module), opts, :docs)
  end

  defp apply_plugins(%ProviderIR{} = provider_ir, plugin_modules, opts, kind) do
    Enum.reduce(plugin_modules, provider_ir, fn plugin_module, acc ->
      case plugin_module.transform(acc, opts) do
        %ProviderIR{} = provider_ir ->
          provider_ir

        other ->
          raise ArgumentError,
                "expected #{kind} plugin #{inspect(plugin_module)} to return PristineCodegen.ProviderIR, got: #{inspect(other)}"
      end
    end)
  end

  defp merge_source_dataset(definition, %Dataset{} = dataset) do
    definition
    |> Map.update(:operations, dataset.operations, &(&1 ++ dataset.operations))
    |> Map.update(:schemas, dataset.schemas, &(&1 ++ dataset.schemas))
    |> Map.update(:auth_policies, dataset.auth_policies, &(&1 ++ dataset.auth_policies))
    |> Map.update(
      :pagination_policies,
      dataset.pagination_policies,
      &(&1 ++ dataset.pagination_policies)
    )
    |> Map.update(
      :docs_inventory,
      dataset.docs_inventory,
      &deep_merge(&1, dataset.docs_inventory)
    )
    |> Map.update(
      :fingerprints,
      dataset.fingerprints,
      &merge_fingerprints(&1, dataset.fingerprints)
    )
  end

  defp merge_fingerprints(left, right) do
    deep_merge(left, right)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      :sources, left_value, right_value when is_list(left_value) and is_list(right_value) ->
        left_value ++ right_value

      :guides, left_value, right_value when is_list(left_value) and is_list(right_value) ->
        left_value ++ right_value

      :examples, left_value, right_value when is_list(left_value) and is_list(right_value) ->
        left_value ++ right_value

      _key, left_value, right_value ->
        deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(left, right) when is_list(left) and is_list(right), do: left ++ right
  defp deep_merge(_left, right), do: right

  defp missing_paths(compilation, expected_files) do
    expected_files
    |> Enum.reject(&File.exists?(Artifacts.absolute_path(compilation, &1)))
    |> Enum.map(& &1.relative_path)
    |> Enum.sort()
  end

  defp stale_paths(compilation, expected_files, missing_paths) do
    expected_files
    |> Enum.reject(fn rendered_file ->
      absolute_path = Artifacts.absolute_path(compilation, rendered_file)

      case File.read(absolute_path) do
        {:ok, contents} -> contents == rendered_file.contents
        {:error, _reason} -> true
      end
    end)
    |> Enum.map(& &1.relative_path)
    |> Enum.reject(&(&1 in missing_paths))
    |> Enum.sort()
  end

  defp forbidden_paths(provider_ir, project_root) do
    provider_ir.artifact_plan.forbidden_paths
    |> Enum.filter(&File.exists?(Path.join(project_root, &1)))
    |> Enum.sort()
  end
end
