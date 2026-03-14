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
  alias Pristine.OpenAPI.Security

  @type run_option :: Pristine.OpenAPI.Profile.option()

  @spec run(atom(), [String.t()], [run_option()]) :: Result.t()
  def run(profile, spec_files, opts \\ [])
      when is_atom(profile) and is_list(spec_files) and is_list(opts) do
    open_api = ensure_generator_available!()
    security_metadata = security_metadata(spec_files, opts)

    Profile.install(profile, opts)
    reader_state = reader_state(profile, spec_files)
    install_renderer_metadata(profile, opts, reader_state, security_metadata)

    try do
      generator_state = open_api.run(Atom.to_string(profile), spec_files)

      Result.from_generator_state(
        generator_state,
        source_contexts: Keyword.get(opts, :source_contexts, %{}),
        security_metadata: security_metadata
      )
    after
      RendererMetadata.delete(profile)
    end
  end

  @spec generated_sources(map()) :: %{String.t() => String.t()}
  def generated_sources(%{files: files}) when is_list(files) do
    files
    |> Enum.flat_map(fn
      %{location: location, contents: contents}
      when is_binary(location) and not is_nil(contents) and contents != "" ->
        [{location, IO.iodata_to_binary(contents)}]

      _other ->
        []
    end)
    |> Map.new()
  end

  @spec generator_state(Result.t() | map()) :: map()
  def generator_state(%{generator_state: generator_state}) when is_map(generator_state),
    do: generator_state

  def generator_state(generator_state) when is_map(generator_state), do: generator_state

  defp security_metadata(spec_files, opts) do
    Keyword.get_lazy(opts, :security_metadata, fn ->
      spec_files
      |> Kernel.++(Keyword.get(opts, :supplemental_files, []))
      |> Security.read()
    end)
  end

  defp install_security_fallback(_profile, opts, security_metadata) do
    if Keyword.has_key?(opts, :security_metadata),
      do: [],
      else: [security_fallback_metadata: security_metadata]
  end

  defp reader_state(profile, spec_files) do
    profile
    |> Atom.to_string()
    |> OpenAPI.Call.new(spec_files)
    |> OpenAPI.State.new()
    |> OpenAPI.Reader.run()
  end

  defp install_renderer_metadata(profile, opts, reader_state, security_metadata) do
    metadata =
      install_security_fallback(profile, opts, security_metadata)
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
