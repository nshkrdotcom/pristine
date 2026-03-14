defmodule Pristine.OpenAPI.Bridge do
  @moduledoc """
  Generic bridge for invoking `oapi_generator` with a Pristine-targeted profile.

  This keeps `pristine` focused on the reusable generation contract instead of
  reimplementing OpenAPI ingestion.
  """

  @compile {:no_warn_undefined, [OpenAPI, OpenAPI.Call, OpenAPI.State, OpenAPI.Reader]}

  alias Pristine.OpenAPI.Profile
  alias Pristine.OpenAPI.RendererMetadata
  alias Pristine.OpenAPI.Result

  @type run_option :: Pristine.OpenAPI.Profile.option()

  @spec run(atom(), [String.t()], [run_option()]) :: Result.t()
  def run(profile, spec_files, opts \\ [])
      when is_atom(profile) and is_list(spec_files) and is_list(opts) do
    open_api = ensure_generator_available!()

    Profile.install(profile, opts)
    reader_state = reader_state(profile, spec_files)
    install_renderer_metadata(profile, reader_state)

    try do
      generator_state = open_api.run(Atom.to_string(profile), spec_files)

      Result.from_generator_state(
        generator_state,
        source_contexts: Keyword.get(opts, :source_contexts, %{})
      )
    after
      RendererMetadata.delete(profile)
    end
  end

  @spec generated_sources(map()) :: %{String.t() => String.t()}
  def generated_sources(%{docs_manifest: %{"generated_files" => files}}) when is_list(files) do
    files
    |> Enum.filter(&(is_binary(&1) and File.exists?(&1)))
    |> Enum.map(&{&1, File.read!(&1)})
    |> Map.new()
  end

  defp reader_state(profile, spec_files) do
    profile
    |> Atom.to_string()
    |> OpenAPI.Call.new(spec_files)
    |> OpenAPI.State.new()
    |> OpenAPI.Reader.run()
  end

  defp install_renderer_metadata(profile, reader_state) do
    metadata =
      []
      |> Keyword.put(:schema_specs_by_path, Map.get(reader_state, :schema_specs_by_path, %{}))
      |> Keyword.put(:spec_metadata_source, Map.get(reader_state, :spec))

    RendererMetadata.put(profile, metadata)
  end

  defp ensure_generator_available! do
    if Code.ensure_loaded?(OpenAPI) do
      OpenAPI
    else
      raise """
      oapi_generator is required to use Pristine.OpenAPI.Bridge.

      Add it as a build-time dependency, for example:

          {:oapi_generator, "~> 0.4", only: [:dev, :test], runtime: false}
      """
    end
  end
end
