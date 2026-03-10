defmodule Pristine.OpenAPI.Bridge do
  @moduledoc """
  Generic bridge for invoking `oapi_generator` with a Pristine-targeted profile.

  This keeps `pristine` focused on the reusable generation contract instead of
  reimplementing OpenAPI ingestion.
  """

  alias Pristine.OpenAPI.Profile

  @type run_option :: Pristine.OpenAPI.Profile.option()

  @spec run(atom(), [String.t()], [run_option()]) :: map()
  def run(profile, spec_files, opts \\ [])
      when is_atom(profile) and is_list(spec_files) and is_list(opts) do
    ensure_generator_available!()
    Profile.install(profile, opts)
    apply(OpenAPI, :run, [Atom.to_string(profile), spec_files])
  end

  @spec generated_sources(map()) :: %{String.t() => String.t()}
  def generated_sources(%{files: files}) when is_list(files) do
    Map.new(files, fn %{location: location, contents: contents} ->
      {location, IO.iodata_to_binary(contents)}
    end)
  end

  defp ensure_generator_available! do
    if Code.ensure_loaded?(OpenAPI) do
      :ok
    else
      raise """
      oapi_generator is required to use Pristine.OpenAPI.Bridge.

      Add it as a build-time dependency, for example:

          {:oapi_generator, "~> 0.4", only: [:dev, :test], runtime: false}
      """
    end
  end
end
