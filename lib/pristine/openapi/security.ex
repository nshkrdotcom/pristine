defmodule Pristine.OpenAPI.Security do
  @moduledoc false

  @http_methods ~w(get put post delete options head patch trace)

  @type operation_key :: {atom(), String.t()}
  @type metadata :: %{
          security_schemes: map(),
          security: [map()] | nil,
          operations: %{optional(operation_key()) => [map()] | nil}
        }

  @spec read([String.t()]) :: metadata()
  def read(spec_files) when is_list(spec_files) do
    Enum.reduce(spec_files, %{security_schemes: %{}, security: nil, operations: %{}}, fn path,
                                                                                         acc ->
      spec = decode_file(path)
      root_security = normalize_security(Map.get(spec, "security"))

      operation_security =
        spec
        |> Map.get("paths", %{})
        |> normalize_operations(root_security)

      %{
        security_schemes:
          Map.merge(
            acc.security_schemes,
            normalize_security_schemes(get_in(spec, ["components", "securitySchemes"]))
          ),
        security: acc.security || root_security,
        operations: Map.merge(acc.operations, operation_security)
      }
    end)
  end

  defp decode_file(path) do
    path
    |> Path.extname()
    |> decode_file_by_extension(path)
  end

  defp normalize_operations(paths, root_security) when is_map(paths) do
    Enum.reduce(paths, %{}, fn path_entry, acc ->
      normalize_path_operations(path_entry, acc, root_security)
    end)
  end

  defp normalize_operations(_paths, _root_security), do: %{}

  defp decode_file_by_extension(ext, path) when ext in [".yaml", ".yml"] do
    YamlElixir.read_from_file!(path)
  end

  defp decode_file_by_extension(".json", path) do
    path |> File.read!() |> Jason.decode!()
  end

  defp decode_file_by_extension(_ext, path) do
    path
    |> File.read!()
    |> decode_file_contents(path)
  end

  defp decode_file_contents(contents, path) do
    case Jason.decode(contents) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> YamlElixir.read_from_file!(path)
    end
  end

  defp normalize_path_operations({path, item}, acc, root_security) do
    Enum.reduce(@http_methods, acc, fn method, operation_acc ->
      put_operation_security(operation_acc, item, method, path, root_security)
    end)
  end

  defp put_operation_security(acc, item, method, path, root_security) do
    case Map.get(item, method) do
      operation when is_map(operation) ->
        Map.put(acc, {String.to_atom(method), path}, operation_security(operation, root_security))

      _other ->
        acc
    end
  end

  defp operation_security(operation, root_security) do
    if Map.has_key?(operation, "security") do
      normalize_security(operation["security"])
    else
      root_security
    end
  end

  defp normalize_security_schemes(schemes) when is_map(schemes) do
    Enum.reduce(schemes, %{}, fn {name, scheme}, acc ->
      Map.put(acc, to_string(name), deep_stringify_keys(scheme))
    end)
  end

  defp normalize_security_schemes(_schemes), do: %{}

  defp normalize_security(nil), do: nil

  defp normalize_security(requirements) when is_list(requirements) do
    Enum.map(requirements, fn
      requirement when is_map(requirement) ->
        Enum.reduce(requirement, %{}, fn {scheme, scopes}, acc ->
          Map.put(acc, to_string(scheme), normalize_scopes(scopes))
        end)

      _other ->
        %{}
    end)
  end

  defp normalize_security(_requirements), do: nil

  defp normalize_scopes(nil), do: []
  defp normalize_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)
  defp normalize_scopes(scope), do: [to_string(scope)]

  defp deep_stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), deep_stringify_keys(nested)} end)
  end

  defp deep_stringify_keys(value) when is_list(value) do
    Enum.map(value, &deep_stringify_keys/1)
  end

  defp deep_stringify_keys(value), do: value
end
