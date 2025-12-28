defmodule Pristine.Codegen.Resource do
  @moduledoc """
  Generates resource modules for grouped endpoints.

  Resource modules provide a namespace for related API endpoints,
  following the pattern `client.models.create()` seen in modern SDKs.
  """

  alias Pristine.Manifest.Endpoint

  @doc """
  Groups endpoints by their resource field.

  Returns a map where keys are resource names (or nil for ungrouped)
  and values are lists of endpoints.
  """
  @spec group_by_resource([Endpoint.t()]) :: %{(String.t() | nil) => [Endpoint.t()]}
  def group_by_resource(endpoints) do
    Enum.group_by(endpoints, & &1.resource)
  end

  @doc """
  Renders all resource modules for a list of endpoints.

  Returns a map of module name to source code. Endpoints with
  `resource: nil` are excluded.
  """
  @spec render_all_resource_modules(String.t(), [Endpoint.t()]) :: %{String.t() => String.t()}
  def render_all_resource_modules(namespace, endpoints) do
    endpoints
    |> group_by_resource()
    |> Enum.reject(fn {resource, _} -> is_nil(resource) end)
    |> Enum.map(fn {resource, eps} ->
      module_name = resource_to_module_name(namespace, resource)
      code = render_resource_module(module_name, resource, eps)
      {module_name, code}
    end)
    |> Map.new()
  end

  @doc """
  Renders a single resource module.
  """
  @spec render_resource_module(String.t(), String.t(), [Endpoint.t()]) :: String.t()
  def render_resource_module(module_name, resource, endpoints) do
    resource_title = resource |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{resource_title} resource endpoints.

      This module provides functions for interacting with #{resource} resources.
      \"\"\"

      defstruct [:context]

      @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

      @doc "Create a resource module instance with the given client."
      @spec with_client(%{context: Pristine.Core.Context.t()}) :: t()
      def with_client(%{context: context}) do
        %__MODULE__{context: context}
      end

    #{render_endpoint_functions(endpoints)}
    end
    """
  end

  @doc """
  Converts a resource name to a module name.

  ## Examples

      iex> Resource.resource_to_module_name("MyAPI", "models")
      "MyAPI.Models"

      iex> Resource.resource_to_module_name("MyAPI", "my_resource")
      "MyAPI.MyResource"
  """
  @spec resource_to_module_name(String.t(), String.t()) :: String.t()
  def resource_to_module_name(namespace, resource) do
    module_part = resource |> String.split("_") |> Enum.map_join(&String.capitalize/1)
    "#{namespace}.#{module_part}"
  end

  # Private functions

  defp render_endpoint_functions(endpoints) do
    Enum.map_join(endpoints, "\n", &render_endpoint_function/1)
  end

  defp render_endpoint_function(%Endpoint{} = endpoint) do
    fn_name = endpoint.id
    doc = render_doc(endpoint)
    spec = render_spec(fn_name)

    """
      #{doc}#{spec}  def #{fn_name}(%__MODULE__{context: context}, payload, opts \\\\ []) do
        Pristine.Runtime.execute(context, #{inspect(endpoint.id)}, payload, opts)
      end
    """
  end

  defp render_doc(%Endpoint{description: nil}), do: ""
  defp render_doc(%Endpoint{description: ""}), do: ""

  defp render_doc(%Endpoint{description: desc}) do
    """
    @doc \"\"\"
      #{String.trim(desc)}
      \"\"\"
    """
  end

  defp render_spec(fn_name) do
    """
    @spec #{fn_name}(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
    """
  end
end
