defmodule Pristine.ErrorTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.Response
  alias Pristine.Error

  describe "from_response/1" do
    test "creates bad_request error for 400" do
      response = %Response{status: 400, body: "Bad request"}
      error = Error.from_response(response)

      assert error.type == :bad_request
      assert error.status == 400
      assert error.body == "Bad request"
    end

    test "creates authentication error for 401" do
      response = %Response{status: 401, body: "Unauthorized"}
      error = Error.from_response(response)

      assert error.type == :authentication
      assert error.status == 401
    end

    test "creates permission_denied error for 403" do
      response = %Response{status: 403}
      error = Error.from_response(response)

      assert error.type == :permission_denied
      assert error.status == 403
    end

    test "creates not_found error for 404" do
      response = %Response{status: 404}
      error = Error.from_response(response)

      assert error.type == :not_found
      assert error.status == 404
    end

    test "creates conflict error for 409" do
      response = %Response{status: 409}
      error = Error.from_response(response)

      assert error.type == :conflict
      assert error.status == 409
    end

    test "creates unprocessable_entity error for 422" do
      response = %Response{status: 422}
      error = Error.from_response(response)

      assert error.type == :unprocessable_entity
      assert error.status == 422
    end

    test "creates rate_limit error for 429" do
      response = %Response{status: 429}
      error = Error.from_response(response)

      assert error.type == :rate_limit
      assert error.status == 429
    end

    test "creates internal_server error for 5xx" do
      for status <- [500, 502, 503, 504] do
        response = %Response{status: status}
        error = Error.from_response(response)
        assert error.type == :internal_server
        assert error.status == status
      end
    end

    test "creates unknown error for unrecognized status codes" do
      for status <- [418, 451] do
        response = %Response{status: status}
        error = Error.from_response(response)
        assert error.type == :unknown
        assert error.status == status
      end
    end

    test "includes response body in error" do
      response = %Response{status: 400, body: ~s({"error": "invalid"})}
      error = Error.from_response(response)

      assert error.body == ~s({"error": "invalid"})
    end

    test "includes headers in response" do
      response = %Response{status: 429, headers: %{"retry-after" => "60"}}
      error = Error.from_response(response)

      assert error.response.headers == %{"retry-after" => "60"}
    end
  end

  describe "connection_error/1" do
    test "creates connection error with reason" do
      error = Error.connection_error(:econnrefused)

      assert error.type == :connection
      assert error.message =~ "Connection failed"
      assert error.message =~ "econnrefused"
    end

    test "handles timeout reason" do
      error = Error.connection_error(:timeout)

      assert error.type == :connection
      assert error.message =~ "timeout"
    end
  end

  describe "timeout_error/0" do
    test "creates timeout error" do
      error = Error.timeout_error()

      assert error.type == :timeout
      assert error.message == "Request timed out"
    end
  end

  describe "message/1" do
    test "returns custom message if set" do
      error = %Error{type: :rate_limit, status: 429, message: "Custom rate limit message"}
      assert Error.message(error) == "Custom rate limit message"
    end

    test "returns default message for type if no custom message" do
      error = %Error{type: :rate_limit, status: 429}
      assert Error.message(error) == "Rate limit exceeded"
    end

    test "returns appropriate messages for all types" do
      types_and_messages = [
        {:bad_request, "Bad request"},
        {:authentication, "Authentication failed"},
        {:permission_denied, "Permission denied"},
        {:not_found, "Resource not found"},
        {:conflict, "Conflict"},
        {:unprocessable_entity, "Unprocessable entity"},
        {:rate_limit, "Rate limit exceeded"},
        {:internal_server, "Internal server error"},
        {:timeout, "Request timed out"},
        {:connection, "Connection failed"},
        {:unknown, "Unknown error"}
      ]

      for {type, expected_message} <- types_and_messages do
        error = %Error{type: type}
        assert Error.message(error) == expected_message
      end
    end
  end

  describe "retriable?/1" do
    test "returns true for retriable error types" do
      retriable_types = [:rate_limit, :internal_server, :timeout, :connection]

      for type <- retriable_types do
        error = %Error{type: type}
        assert Error.retriable?(error) == true, "Expected #{type} to be retriable"
      end
    end

    test "returns false for non-retriable error types" do
      non_retriable_types = [
        :bad_request,
        :authentication,
        :permission_denied,
        :not_found,
        :conflict,
        :unprocessable_entity,
        :unknown
      ]

      for type <- non_retriable_types do
        error = %Error{type: type}
        assert Error.retriable?(error) == false, "Expected #{type} to not be retriable"
      end
    end

    test "respects retry override in response headers" do
      # Non-retriable status but header says retry
      response = %Response{status: 400, headers: %{"x-should-retry" => "true"}}
      error = Error.from_response(response)
      assert Error.retriable?(error) == true

      # Retriable status but header says don't retry
      response = %Response{status: 500, headers: %{"x-should-retry" => "false"}}
      error = Error.from_response(response)
      assert Error.retriable?(error) == false
    end
  end

  describe "Exception implementation" do
    test "Error is an exception" do
      error = %Error{type: :rate_limit, message: "Too many requests"}
      assert Exception.message(error) == "Too many requests"
    end

    test "can be raised" do
      assert_raise Error, "Test error message", fn ->
        raise %Error{type: :bad_request, message: "Test error message"}
      end
    end
  end
end
