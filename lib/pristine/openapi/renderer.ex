if Code.ensure_loaded?(OpenAPI.Renderer) do
  defmodule Pristine.OpenAPI.Renderer do
    @moduledoc """
    Renderer overrides for Pristine-targeted generated operation surfaces.

    The default upstream renderer stays in place for modules, schemas, docs, and
    file layout. This module only overrides the operation shape so generated code
    can accept a single params map and emit Pristine request partitions.
    """

    use OpenAPI.Renderer

    alias OpenAPI.Processor.Operation
    alias OpenAPI.Processor.Operation.Param
    alias OpenAPI.Renderer.Operation, as: OperationRenderer
    alias OpenAPI.Renderer.State
    alias OpenAPI.Renderer.Util

    @multipart_content_type "multipart/form-data"

    @impl OpenAPI.Renderer
    def render_operation_spec(state, operation) do
      %Operation{function_name: name, responses: responses} = operation

      params = quote(do: params :: map())
      opts = quote(do: opts :: keyword())
      return_type = render_return_type(state, responses)

      case config(state)[:types][:specs] do
        false ->
          []

        :callback ->
          quote do
            @callback unquote(name)(unquote(params), unquote(opts)) :: unquote(return_type)
          end

        :callback_comprehensive ->
          [
            quote do
              @callback unquote(name)(unquote(params)) :: unquote(return_type)
            end,
            quote do
              @callback unquote(name)(unquote(params), unquote(opts)) :: unquote(return_type)
            end
          ]

        :spec_comprehensive ->
          [
            quote do
              @spec unquote(name)(unquote(params)) :: unquote(return_type)
            end,
            quote do
              @spec unquote(name)(unquote(params), unquote(opts)) :: unquote(return_type)
            end
          ]

        _default ->
          quote do
            @spec unquote(name)(unquote(params), unquote(opts)) :: unquote(return_type)
          end
      end
    end

    @impl OpenAPI.Renderer
    def render_operation_function(state, operation) do
      %Operation{
        function_name: function_name,
        module_name: module_name,
        request_body: request_body,
        request_method: request_method,
        request_path: request_path,
        responses: responses
      } = operation

      partition_spec = request_partition_spec(state, operation)

      module_name =
        Module.concat([
          config(state)[:base_module],
          module_name
        ])

      request =
        [
          quote(do: {:args, params}),
          quote(do: {:call, {unquote(module_name), unquote(function_name)}}),
          quote(do: {:url, render_path(unquote(request_path), partition.path_params)}),
          quote(do: {:method, unquote(request_method)}),
          quote(do: {:path_params, partition.path_params}),
          quote(do: {:query, partition.query}),
          quote(do: {:body, partition.body}),
          quote(do: {:form_data, partition.form_data}),
          quote(do: {:auth, partition.auth}),
          OperationRenderer.render_call_request_info(
            state,
            request_body,
            config(state)[:operation_call][:request]
          ),
          render_response_info(state, responses),
          quote(do: {:opts, opts})
        ]
        |> Enum.reject(&is_nil/1)

      quote do
        def unquote(function_name)(params \\ %{}, opts \\ [])
            when is_map(params) and is_list(opts) do
          client = opts[:client] || @default_client
          partition = partition(params, unquote(Macro.escape(partition_spec)))

          client.request(%{
            unquote_splicing(request)
          })
        end
      end
    end

    defp request_partition_spec(state, operation) do
      %Operation{
        request_body: request_body,
        request_path_parameters: path_params,
        request_query_parameters: query_params
      } = operation

      {multipart_request_body, standard_request_body} =
        Enum.split_with(request_body, fn {content_type, _type} ->
          String.starts_with?(content_type, @multipart_content_type)
        end)

      %{
        auth: {"auth", :auth},
        path: key_specs(path_params),
        query: key_specs(query_params),
        body: payload_spec(state, standard_request_body, {"body", :body}),
        form_data: payload_spec(state, multipart_request_body, {"form_data", :form_data})
      }
    end

    defp payload_spec(_state, [], _fallback_key), do: %{mode: :none}

    defp payload_spec(state, request_body, fallback_key) do
      keys =
        request_body
        |> Enum.reduce(MapSet.new(), fn {_content_type, type}, keys ->
          MapSet.union(keys, request_field_names(state, type))
        end)
        |> MapSet.to_list()
        |> Enum.sort()

      if keys == [] do
        %{mode: :key, key: fallback_key}
      else
        %{mode: :keys, keys: Enum.map(keys, &{&1, String.to_atom(&1)})}
      end
    end

    defp key_specs(params) do
      Enum.map(params, fn %Param{name: name} -> {name, String.to_atom(name)} end)
    end

    defp request_field_names(state, {:union, types}) do
      Enum.reduce(types, MapSet.new(), fn type, names ->
        MapSet.union(names, request_field_names(state, type))
      end)
    end

    defp request_field_names(state, ref) when is_reference(ref) do
      case Map.get(state.schemas, ref) do
        %{fields: fields} ->
          Enum.reduce(fields, MapSet.new(), fn field, names -> MapSet.put(names, field.name) end)

        nil ->
          MapSet.new()
      end
    end

    defp request_field_names(_state, _type), do: MapSet.new()

    defp render_response_info(_state, []), do: nil

    defp render_response_info(state, responses) do
      items =
        responses
        |> Enum.sort_by(fn {status_or_default, _schemas} -> status_or_default end)
        |> Enum.map(fn {status_or_default, schemas} ->
          type = Util.to_readable_type(state, {:union, Map.values(schemas)})

          quote do
            {unquote(status_or_default), unquote(type)}
          end
        end)

      quote do
        {:response, unquote(items)}
      end
    end

    defp render_return_type(_state, []), do: quote(do: :ok)

    defp render_return_type(state, responses) do
      %State{implementation: implementation} = state

      {success, error} =
        responses
        |> Enum.reject(fn {_status, schemas} -> map_size(schemas) == 0 end)
        |> Enum.reject(fn {status, _schemas} -> status >= 300 and status < 400 end)
        |> Enum.split_with(fn {status, _schemas} -> status < 300 end)

      ok =
        if success == [] do
          quote(do: :ok)
        else
          type =
            success
            |> Enum.flat_map(fn {_status, schemas} -> Map.values(schemas) end)
            |> then(&implementation.render_type(state, {:union, &1}))

          quote(do: {:ok, unquote(type)})
        end

      error =
        case config(state)[:types][:error] do
          nil ->
            render_error_union(state, error)

          error_type ->
            quote(do: {:error, unquote(render_configured_type(state, error_type))})
        end

      {:|, [], [ok, error]}
    end

    defp render_error_union(_state, []), do: quote(do: :error)

    defp render_error_union(state, error) do
      %State{implementation: implementation} = state

      type =
        error
        |> Enum.flat_map(fn {_status, schemas} -> Map.values(schemas) end)
        |> then(&implementation.render_type(state, {:union, &1}))

      quote(do: {:error, unquote(type)})
    end

    defp render_configured_type(state, {module, type}) when is_atom(module) and is_atom(type) do
      %State{implementation: implementation} = state
      implementation.render_type(state, {module, type})
    end

    defp render_configured_type(_state, module) when is_atom(module) do
      quote(do: unquote(module).t())
    end

    defp config(%State{profile: profile}) do
      Application.get_env(:oapi_generator, profile, [])
      |> Keyword.get(:output, [])
    end
  end
else
  defmodule Pristine.OpenAPI.Renderer do
    @moduledoc false

    def unavailable! do
      raise """
      oapi_generator is required to use Pristine.OpenAPI.Renderer.

      Add it as a build-time dependency, for example:

          {:oapi_generator, "~> 0.4", only: [:dev, :test], runtime: false}
      """
    end
  end
end
