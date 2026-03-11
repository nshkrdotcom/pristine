defmodule Pristine.OpenAPI.Bridge do
  @moduledoc """
  Generic bridge for invoking `oapi_generator` with a Pristine-targeted profile.

  This keeps `pristine` focused on the reusable generation contract instead of
  reimplementing OpenAPI ingestion.
  """

  alias Pristine.OpenAPI.Profile
  alias Pristine.OpenAPI.Security

  @type run_option :: Pristine.OpenAPI.Profile.option()

  @spec run(atom(), [String.t()], [run_option()]) :: map()
  def run(profile, spec_files, opts \\ [])
      when is_atom(profile) and is_list(spec_files) and is_list(opts) do
    open_api = ensure_generator_available!()
    supplemental_files = Keyword.get(opts, :supplemental_files, [])

    opts =
      Keyword.put_new(
        opts,
        :security_metadata,
        Security.read(spec_files ++ supplemental_files)
      )

    Profile.install(profile, opts)
    open_api.run(Atom.to_string(profile), spec_files)
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
