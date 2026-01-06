defmodule Tinkex.Types.ErrorTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{RequestErrorCategory, RequestFailedResponse}
  alias Tinkex.Error

  describe "RequestErrorCategory" do
    test "parse/1 parses server" do
      assert RequestErrorCategory.parse("server") == :server
      assert RequestErrorCategory.parse("SERVER") == :server
      assert RequestErrorCategory.parse("Server") == :server
    end

    test "parse/1 parses user" do
      assert RequestErrorCategory.parse("user") == :user
      assert RequestErrorCategory.parse("USER") == :user
    end

    test "parse/1 returns unknown for invalid values" do
      assert RequestErrorCategory.parse("invalid") == :unknown
      assert RequestErrorCategory.parse("") == :unknown
      assert RequestErrorCategory.parse(nil) == :unknown
    end

    test "to_string/1 converts atoms" do
      assert RequestErrorCategory.to_string(:unknown) == "unknown"
      assert RequestErrorCategory.to_string(:server) == "server"
      assert RequestErrorCategory.to_string(:user) == "user"
    end

    test "retryable?/1 returns correct values" do
      assert RequestErrorCategory.retryable?(:server) == true
      assert RequestErrorCategory.retryable?(:unknown) == true
      assert RequestErrorCategory.retryable?(:user) == false
    end
  end

  describe "RequestFailedResponse" do
    test "new/2 creates response" do
      response = RequestFailedResponse.new("Something went wrong", :server)

      assert response.error == "Something went wrong"
      assert response.category == :server
    end

    test "from_json/1 parses with string keys" do
      json = %{
        "error" => "Bad request",
        "category" => "user"
      }

      response = RequestFailedResponse.from_json(json)

      assert response.error == "Bad request"
      assert response.category == :user
    end

    test "from_json/1 parses with atom keys" do
      json = %{
        error: "Server error",
        category: "server"
      }

      response = RequestFailedResponse.from_json(json)

      assert response.error == "Server error"
      assert response.category == :server
    end

    test "from_json/1 handles missing category" do
      json = %{"error" => "Unknown error"}
      response = RequestFailedResponse.from_json(json)

      assert response.error == "Unknown error"
      assert response.category == :unknown
    end
  end

  describe "Tinkex.Error" do
    test "new/2 creates error with defaults" do
      error = Error.new(:api_connection, "Connection failed")

      assert error.type == :api_connection
      assert error.message == "Connection failed"
      assert error.status == nil
      assert error.category == nil
      assert error.data == nil
      assert error.retry_after_ms == nil
    end

    test "new/3 creates error with options" do
      error =
        Error.new(:api_status, "Bad request",
          status: 400,
          category: :user,
          data: %{"field" => "invalid"},
          retry_after_ms: 5000
        )

      assert error.type == :api_status
      assert error.message == "Bad request"
      assert error.status == 400
      assert error.category == :user
      assert error.data == %{"field" => "invalid"}
      assert error.retry_after_ms == 5000
    end

    test "from_response/2 creates error from HTTP response" do
      error =
        Error.from_response(500, %{
          "error" => "Internal server error",
          "category" => "server"
        })

      assert error.type == :api_status
      assert error.message == "Internal server error"
      assert error.status == 500
      assert error.category == :server
    end

    test "from_response/2 handles message field" do
      error = Error.from_response(400, %{"message" => "Validation failed"})

      assert error.message == "Validation failed"
    end

    test "from_response/2 defaults to Unknown error" do
      error = Error.from_response(500, %{})

      assert error.message == "Unknown error"
    end

    test "user_error?/1 returns true for user category" do
      error = Error.new(:api_status, "Bad request", category: :user)
      assert Error.user_error?(error) == true
    end

    test "user_error?/1 returns true for 4xx status codes" do
      assert Error.user_error?(Error.new(:api_status, "Bad request", status: 400)) == true
      assert Error.user_error?(Error.new(:api_status, "Not found", status: 404)) == true
      assert Error.user_error?(Error.new(:api_status, "Forbidden", status: 403)) == true
    end

    test "user_error?/1 returns false for retryable 4xx codes" do
      # 408 Request Timeout
      assert Error.user_error?(Error.new(:api_status, "Timeout", status: 408)) == false
      # 410 Gone (may indicate temp unavailability)
      assert Error.user_error?(Error.new(:api_status, "Gone", status: 410)) == false
      # 429 Too Many Requests
      assert Error.user_error?(Error.new(:api_status, "Rate limited", status: 429)) == false
    end

    test "user_error?/1 returns false for 5xx status codes" do
      assert Error.user_error?(Error.new(:api_status, "Server error", status: 500)) == false
      assert Error.user_error?(Error.new(:api_status, "Unavailable", status: 503)) == false
    end

    test "user_error?/1 returns false for errors without status or category" do
      assert Error.user_error?(Error.new(:api_connection, "Connection failed")) == false
    end

    test "retryable?/1 is inverse of user_error?/1" do
      user_error = Error.new(:api_status, "Bad request", status: 400)
      server_error = Error.new(:api_status, "Server error", status: 500)

      assert Error.retryable?(user_error) == false
      assert Error.retryable?(server_error) == true
    end

    test "format/1 formats error without status" do
      error = Error.new(:api_connection, "Connection failed")
      assert Error.format(error) == "[api_connection] Connection failed"
    end

    test "format/1 formats error with status" do
      error = Error.new(:api_status, "Bad request", status: 400)
      assert Error.format(error) == "[api_status (400)] Bad request"
    end

    test "String.Chars implementation" do
      error = Error.new(:api_timeout, "Request timed out")
      assert to_string(error) == "[api_timeout] Request timed out"
    end
  end
end
