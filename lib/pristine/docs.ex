defmodule Pristine.Docs do
  @moduledoc """
  Generates documentation from Pristine manifests.

  This module provides utilities for generating readable documentation from
  manifest definitions, including endpoint descriptions, type schemas,
  and usage examples.

  ## Usage

      {:ok, markdown} = Pristine.Docs.generate(manifest)
      {:ok, html} = Pristine.Docs.generate_html(manifest)

  ## Options

    * `:examples` - Include example requests (default: false)
    * `:include_types` - Include type reference section (default: true)

  """

  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint

  @type option :: {:examples, boolean()} | {:include_types, boolean()}

  @doc """
  Generates Markdown documentation from a Pristine manifest.

  ## Parameters

    * `manifest` - A loaded Pristine manifest
    * `opts` - Generation options

  ## Options

    * `:examples` - Include example requests (default: false)
    * `:include_types` - Include type reference section (default: true)

  ## Returns

    * `{:ok, markdown}` - The generated Markdown documentation

  """
  @spec generate(Manifest.t(), [option]) :: {:ok, String.t()} | {:error, term()}
  def generate(%Manifest{} = manifest, opts \\ []) do
    sections = [
      generate_title(manifest),
      generate_overview(manifest),
      generate_toc(manifest),
      generate_endpoints_sections(manifest, opts),
      generate_types_section(manifest, opts)
    ]

    markdown =
      sections
      |> Enum.reject(&(&1 == "" or is_nil(&1)))
      |> Enum.join("\n\n")

    {:ok, markdown}
  end

  @doc """
  Generates HTML documentation from a Pristine manifest.

  ## Parameters

    * `manifest` - A loaded Pristine manifest
    * `opts` - Generation options

  ## Returns

    * `{:ok, html}` - The generated HTML documentation

  """
  @spec generate_html(Manifest.t(), [option]) :: {:ok, String.t()} | {:error, term()}
  def generate_html(%Manifest{} = manifest, opts \\ []) do
    with {:ok, markdown} <- generate(manifest, opts) do
      html = markdown_to_html(markdown, manifest)
      {:ok, html}
    end
  end

  # Private functions - Title and Overview

  defp generate_title(%Manifest{name: name}) do
    "# #{name || "API Documentation"}"
  end

  defp generate_overview(%Manifest{} = manifest) do
    parts = ["## Overview", ""]

    parts =
      if manifest.name do
        parts ++ ["API: **#{manifest.name}**"]
      else
        parts
      end

    parts =
      if manifest.version do
        parts ++ ["Version: #{manifest.version}"]
      else
        parts
      end

    Enum.join(parts, "\n")
  end

  # Private functions - Table of Contents

  defp generate_toc(%Manifest{endpoints: endpoints}) do
    resources =
      endpoints
      |> get_endpoints_list()
      |> Enum.map(& &1.resource)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if Enum.empty?(resources) do
      ""
    else
      items =
        Enum.map(resources, fn resource ->
          name = resource |> to_string() |> capitalize_resource()
          anchor = resource |> to_string() |> String.downcase()
          "- [#{name}](##{anchor})"
        end)

      """
      ## Table of Contents

      #{Enum.join(items, "\n")}
      """
    end
  end

  # Private functions - Endpoints

  defp generate_endpoints_sections(%Manifest{endpoints: endpoints}, opts) do
    endpoints_list = get_endpoints_list(endpoints)

    endpoints_list
    |> Enum.group_by(& &1.resource)
    |> Enum.map_join("\n\n", fn {resource, group} ->
      generate_resource_section(resource, group, opts)
    end)
  end

  defp generate_resource_section(resource, endpoints, opts) do
    section_title =
      if resource do
        "## #{capitalize_resource(resource)}"
      else
        "## Endpoints"
      end

    endpoint_docs =
      Enum.map(endpoints, fn endpoint ->
        generate_endpoint_doc(endpoint, opts)
      end)

    [section_title | endpoint_docs]
    |> Enum.join("\n\n")
  end

  defp generate_endpoint_doc(%Endpoint{} = endpoint, opts) do
    parts = [
      "### #{endpoint.method} #{endpoint.path}"
    ]

    parts =
      if endpoint.description do
        parts ++ [endpoint.description]
      else
        parts
      end

    parts = parts ++ [generate_params_table(endpoint)]

    parts =
      if endpoint.request do
        parts ++ [generate_request_body_doc(endpoint)]
      else
        parts
      end

    parts =
      if endpoint.response do
        parts ++ [generate_response_doc(endpoint)]
      else
        parts
      end

    parts =
      if Keyword.get(opts, :examples, false) do
        parts ++ [generate_example(endpoint)]
      else
        parts
      end

    parts
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join("\n\n")
  end

  defp generate_params_table(%Endpoint{path: path}) do
    path_params = extract_path_params(path)

    if Enum.empty?(path_params) do
      ""
    else
      header =
        "| Parameter | Type | Required | Description |\n|-----------|------|----------|-------------|"

      rows =
        Enum.map(path_params, fn name ->
          "| `#{name}` | string | Yes | Path parameter |"
        end)

      """
      #### Parameters

      #{header}
      #{Enum.join(rows, "\n")}
      """
    end
  end

  defp extract_path_params(path) do
    ~r/\{([^}]+)\}/
    |> Regex.scan(path)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp generate_request_body_doc(%Endpoint{request: nil}), do: ""

  defp generate_request_body_doc(%Endpoint{request: type}) do
    """
    #### Request Body

    Type: [`#{type}`](##{String.downcase(type)})
    """
  end

  defp generate_response_doc(%Endpoint{response: nil}), do: ""

  defp generate_response_doc(%Endpoint{response: type}) do
    """
    #### Response

    Type: [`#{type}`](##{String.downcase(type)})
    """
  end

  defp generate_example(%Endpoint{} = endpoint) do
    fn_name =
      endpoint.id
      |> to_string()
      |> String.replace("-", "_")

    """
    #### Example

    ```elixir
    client = MyAPI.Client.new(api_key: "your-api-key")
    {:ok, response} = MyAPI.Client.#{fn_name}(client, params)
    ```
    """
  end

  # Private functions - Types

  defp generate_types_section(%Manifest{types: types}, _opts) when map_size(types) == 0 do
    ""
  end

  defp generate_types_section(%Manifest{types: types}, _opts) do
    type_docs =
      types
      |> Enum.map(fn {type_name, type_def} ->
        generate_type_doc(type_name, type_def)
      end)

    """
    ## Type Reference

    #{Enum.join(type_docs, "\n\n")}
    """
  end

  defp generate_type_doc(type_name, type_def) do
    parts = ["### #{type_name}"]

    fields = Map.get(type_def, :fields) || Map.get(type_def, "fields") || %{}

    parts =
      if map_size(fields) > 0 do
        parts ++ [generate_fields_table(fields)]
      else
        parts
      end

    Enum.join(parts, "\n\n")
  end

  defp generate_fields_table(fields) do
    header =
      "| Field | Type | Required | Description |\n|-------|------|----------|-------------|"

    rows =
      Enum.map(fields, fn {name, field_def} ->
        field_name = normalize_key(name)
        type = get_field_type(field_def)
        required = if field_required?(field_def), do: "Yes", else: "No"
        desc = get_field_description(field_def)
        "| `#{field_name}` | #{type} | #{required} | #{desc} |"
      end)

    "#{header}\n#{Enum.join(rows, "\n")}"
  end

  defp get_field_type(field_def) when is_map(field_def) do
    Map.get(field_def, :type) || Map.get(field_def, "type") || "string"
  end

  defp get_field_type(_), do: "string"

  defp field_required?(field_def) when is_map(field_def) do
    Map.get(field_def, :required) == true or Map.get(field_def, "required") == true
  end

  defp field_required?(_), do: false

  defp get_field_description(field_def) when is_map(field_def) do
    Map.get(field_def, :description) || Map.get(field_def, "description") || ""
  end

  defp get_field_description(_), do: ""

  # Private functions - HTML conversion

  defp markdown_to_html(markdown, manifest) do
    # manifest.name is always present after validation
    title = manifest.name

    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>#{title}</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          max-width: 900px;
          margin: 0 auto;
          padding: 20px;
          line-height: 1.6;
          color: #333;
        }
        code {
          background: #f5f5f5;
          padding: 2px 6px;
          border-radius: 3px;
          font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
        }
        pre {
          background: #f5f5f5;
          padding: 16px;
          overflow-x: auto;
          border-radius: 4px;
        }
        pre code {
          background: none;
          padding: 0;
        }
        table {
          border-collapse: collapse;
          width: 100%;
          margin: 16px 0;
        }
        th, td {
          border: 1px solid #ddd;
          padding: 8px;
          text-align: left;
        }
        th {
          background: #f5f5f5;
        }
        h1, h2, h3, h4 {
          margin-top: 24px;
          margin-bottom: 16px;
        }
        h1 { border-bottom: 2px solid #eee; padding-bottom: 8px; }
        h2 { border-bottom: 1px solid #eee; padding-bottom: 8px; }
        a { color: #0366d6; text-decoration: none; }
        a:hover { text-decoration: underline; }
      </style>
    </head>
    <body>
    #{convert_markdown_to_html(markdown)}
    </body>
    </html>
    """
  end

  defp convert_markdown_to_html(markdown) do
    markdown
    # Convert code blocks first
    |> convert_code_blocks()
    # Convert headers
    |> String.replace(~r/^#### (.+)$/m, "<h4>\\1</h4>")
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
    # Convert inline code
    |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
    # Convert bold
    |> String.replace(~r/\*\*([^*]+)\*\*/, "<strong>\\1</strong>")
    # Convert links
    |> String.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, "<a href=\"\\2\">\\1</a>")
    # Convert tables
    |> convert_tables()
    # Convert list items
    |> String.replace(~r/^- (.+)$/m, "<li>\\1</li>")
    # Wrap adjacent list items
    |> wrap_lists()
    # Convert paragraphs
    |> convert_paragraphs()
  end

  defp convert_code_blocks(text) do
    Regex.replace(~r/```(\w+)?\n(.*?)```/s, text, fn _, lang, code ->
      lang_attr = if lang && lang != "", do: " class=\"language-#{lang}\"", else: ""
      "<pre><code#{lang_attr}>#{String.trim(code)}</code></pre>"
    end)
  end

  defp convert_tables(text) do
    Regex.replace(~r/\|(.+)\|\n\|[-|]+\|\n((?:\|.+\|\n?)+)/m, text, fn _, header, rows ->
      header_cells =
        header
        |> String.split("|")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map_join("", &"<th>#{&1}</th>")

      row_lines =
        rows
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.map_join("\n", fn row ->
          cells =
            row
            |> String.split("|")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))
            |> Enum.map_join("", &"<td>#{&1}</td>")

          "<tr>#{cells}</tr>"
        end)

      "<table>\n<thead><tr>#{header_cells}</tr></thead>\n<tbody>#{row_lines}</tbody>\n</table>"
    end)
  end

  defp wrap_lists(text) do
    Regex.replace(~r/((?:<li>.+<\/li>\n?)+)/m, text, fn _, items ->
      "<ul>\n#{items}</ul>"
    end)
  end

  defp convert_paragraphs(text) do
    text
    |> String.split("\n\n")
    |> Enum.map_join("\n\n", &convert_paragraph_block/1)
  end

  defp convert_paragraph_block(block) do
    block = String.trim(block)

    cond do
      block == "" -> ""
      String.starts_with?(block, "<") -> block
      true -> "<p>#{block}</p>"
    end
  end

  # Private functions - Helpers

  defp get_endpoints_list(endpoints) when is_map(endpoints) do
    Map.values(endpoints)
  end

  defp get_endpoints_list(endpoints) when is_list(endpoints) do
    endpoints
  end

  defp get_endpoints_list(_), do: []

  defp capitalize_resource(resource) do
    resource
    |> to_string()
    |> String.split("_")
    |> Enum.map_join("", &String.capitalize/1)
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)
end
