defmodule Tinkex.API.RequestTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Request

  describe "prepare_body/4" do
    test "encodes map body as JSON" do
      {:ok, headers, body} =
        Request.prepare_body(
          %{key: "value"},
          [{"content-type", "application/json"}],
          nil,
          []
        )

      assert Jason.decode!(body) == %{"key" => "value"}
      assert is_list(headers)
    end

    test "passes through binary body unchanged" do
      {:ok, _headers, body} =
        Request.prepare_body(
          ~s({"raw": true}),
          [{"content-type", "application/json"}],
          nil,
          []
        )

      assert body == ~s({"raw": true})
    end

    test "handles nil body" do
      {:ok, _headers, body} =
        Request.prepare_body(
          nil,
          [{"content-type", "application/json"}],
          nil,
          []
        )

      assert body == "null"
    end

    test "detects multipart request by files presence" do
      files = %{"file" => {"test.txt", "content"}}

      {:ok, headers, body} =
        Request.prepare_body(
          %{name: "test"},
          [{"content-type", "application/json"}],
          files,
          []
        )

      # Content-type should be multipart
      content_type =
        Enum.find_value(headers, fn
          {k, v} when is_binary(k) -> if String.downcase(k) == "content-type", do: v
          _ -> nil
        end)

      assert String.contains?(content_type, "multipart/form-data")
      assert is_binary(body)
    end

    test "returns error for binary body in multipart request" do
      files = %{"file" => {"test.txt", "content"}}

      result =
        Request.prepare_body(
          "binary body",
          [{"content-type", "application/json"}],
          files,
          []
        )

      assert {:error, {:invalid_multipart_body, :binary}} = result
    end
  end

  describe "format_error/1" do
    test "formats invalid_multipart_body binary error" do
      message = Request.format_error({:invalid_multipart_body, :binary})
      assert message == "multipart body must be a map or keyword list"
    end

    test "formats invalid_multipart_body with value" do
      message = Request.format_error({:invalid_multipart_body, "string"})
      assert String.contains?(message, "multipart body must be a map")
    end

    test "formats invalid_request_files" do
      message = Request.format_error({:invalid_request_files, :bad})
      assert String.contains?(message, "invalid files option")
    end

    test "formats unknown error as inspect" do
      message = Request.format_error(:unknown_error)
      assert message == ":unknown_error"
    end
  end
end
