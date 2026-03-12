defmodule Pristine.OpenAPI.NamedTypedMapFixture do
  @moduledoc false

  alias Pristine.OpenAPI.Bridge

  @spec run_bridge!(atom()) :: map()
  def run_bridge!(label) when is_atom(label) do
    tmp_dir = tmp_dir!(label)
    spec_file = write_spec!(tmp_dir)
    output_dir = Path.join(tmp_dir, "generated")
    profile = unique_profile(label)
    base_module = unique_base_module(label)

    state =
      Bridge.run(
        profile,
        [spec_file],
        base_module: base_module,
        output_dir: output_dir
      )

    %{
      base_module: base_module,
      output_dir: output_dir,
      profile: profile,
      sources: Bridge.generated_sources(state),
      state: state,
      tmp_dir: tmp_dir
    }
  end

  @spec cleanup(map()) :: :ok
  def cleanup(%{profile: profile, tmp_dir: tmp_dir}) do
    Application.delete_env(:oapi_generator, profile)
    File.rm_rf!(tmp_dir)
    :ok
  end

  @spec generated_path?(map(), String.t()) :: boolean()
  def generated_path?(%{sources: sources}, suffix) when is_binary(suffix) do
    Enum.any?(Map.keys(sources), &String.ends_with?(&1, suffix))
  end

  @spec source!(map(), String.t()) :: String.t()
  def source!(%{sources: sources}, suffix) when is_binary(suffix) do
    Enum.find_value(sources, fn {path, source} ->
      if String.ends_with?(path, suffix), do: source
    end) || raise "missing generated source ending with #{suffix}"
  end

  defp write_spec!(tmp_dir) do
    path = Path.join(tmp_dir, "phantom_named_typed_maps.yaml")

    File.write!(
      path,
      """
      openapi: 3.1.0
      info:
        title: Phantom named typed maps
        version: 1.0.0
      components: {}
      paths:
        /oauth/token:
          post:
            tags:
              - OAuth
            operationId: token
            responses:
              '200':
                description: Token response
                content:
                  application/json:
                    schema:
                      type: object
                      required:
                        - owner
                      properties:
                        owner:
                          oneOf:
                            - title: User
                              type: object
                              required:
                                - type
                                - user
                              properties:
                                type:
                                  const: user
                                user:
                                  type: string
                            - title: Workspace
                              type: object
                              required:
                                - type
                                - workspace
                              properties:
                                type:
                                  const: workspace
                                workspace:
                                  const: true
      """
    )

    path
  end

  defp tmp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "pristine-openapi-named-typed-map-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp unique_profile(label) do
    :"pristine_openapi_named_typed_map_#{label}_#{System.unique_integer([:positive])}"
  end

  defp unique_base_module(label) do
    Module.concat([
      Pristine,
      :"OpenAPINamedTypedMap#{label |> to_string() |> Macro.camelize()}#{System.unique_integer([:positive])}"
    ])
  end
end
