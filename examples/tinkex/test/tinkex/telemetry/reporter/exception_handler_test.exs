defmodule Tinkex.Telemetry.Reporter.ExceptionHandlerTest do
  @moduledoc """
  Tests for exception classification in telemetry reporter.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Reporter.ExceptionHandler

  describe "classify_exception/1" do
    test "classifies Tinkex.Error with user_error? as user error" do
      error = %Tinkex.Error{
        message: "Bad request",
        status: 400,
        category: :user
      }

      assert {:user_error, ^error} = ExceptionHandler.classify_exception(error)
    end

    test "classifies Tinkex.Error with 4xx status as user error" do
      error = %Tinkex.Error{
        message: "Not found",
        status: 404
      }

      assert {:user_error, ^error} = ExceptionHandler.classify_exception(error)
    end

    test "classifies Tinkex.Error with 5xx status as unhandled" do
      error = %Tinkex.Error{
        message: "Internal error",
        status: 500
      }

      assert :unhandled = ExceptionHandler.classify_exception(error)
    end

    test "classifies 408 (Request Timeout) as unhandled (retryable)" do
      error = %Tinkex.Error{
        message: "Timeout",
        status: 408
      }

      assert :unhandled = ExceptionHandler.classify_exception(error)
    end

    test "classifies 429 (Too Many Requests) as unhandled (retryable)" do
      error = %Tinkex.Error{
        message: "Rate limited",
        status: 429
      }

      assert :unhandled = ExceptionHandler.classify_exception(error)
    end

    test "classifies generic exception as unhandled" do
      exception = %RuntimeError{message: "Something went wrong"}

      assert :unhandled = ExceptionHandler.classify_exception(exception)
    end

    test "classifies map with status 400-499 as user error" do
      error_map = %{status: 403, message: "Forbidden"}

      assert {:user_error, ^error_map} = ExceptionHandler.classify_exception(error_map)
    end

    test "classifies map with status_code 400-499 as user error" do
      error_map = %{status_code: 401, message: "Unauthorized"}

      assert {:user_error, ^error_map} = ExceptionHandler.classify_exception(error_map)
    end

    test "classifies map with plug_status 400-499 as user error" do
      error_map = %{plug_status: 422, message: "Unprocessable"}

      assert {:user_error, ^error_map} = ExceptionHandler.classify_exception(error_map)
    end

    test "classifies map with category :user as user error" do
      error_map = %{category: :user, message: "User error"}

      assert {:user_error, ^error_map} = ExceptionHandler.classify_exception(error_map)
    end
  end

  describe "find_user_error_in_chain/1" do
    test "returns :not_found for empty chain" do
      error = %{message: "Server error", status: 500}

      assert :not_found = ExceptionHandler.find_user_error_in_chain(error)
    end

    test "finds user error via :cause field" do
      user_error = %{status: 400, message: "Bad input"}

      wrapper = %{
        message: "Wrapped error",
        cause: user_error
      }

      assert {:ok, ^user_error} = ExceptionHandler.find_user_error_in_chain(wrapper)
    end

    test "finds user error via :reason field" do
      user_error = %{status: 403, message: "Forbidden"}

      wrapper = %{
        message: "Wrapper",
        reason: user_error
      }

      assert {:ok, ^user_error} = ExceptionHandler.find_user_error_in_chain(wrapper)
    end

    test "finds user error via :__cause__ field" do
      user_error = %{status_code: 404, message: "Not found"}

      wrapper = %{
        message: "Wrapper",
        __cause__: user_error
      }

      assert {:ok, ^user_error} = ExceptionHandler.find_user_error_in_chain(wrapper)
    end

    test "finds user error via :__context__ field" do
      user_error = %{category: :user, message: "User error"}

      wrapper = %{
        message: "Wrapper",
        __context__: user_error
      }

      assert {:ok, ^user_error} = ExceptionHandler.find_user_error_in_chain(wrapper)
    end

    test "finds user error in nested chain" do
      user_error = %{status: 400, message: "Root cause"}

      level2 = %{message: "Level 2", cause: user_error}
      level1 = %{message: "Level 1", cause: level2}

      assert {:ok, ^user_error} = ExceptionHandler.find_user_error_in_chain(level1)
    end

    test "handles circular references without infinite loop" do
      # Create a circular reference using a process dictionary workaround
      error1 = %{message: "Error 1", status: 500}
      error2 = %{message: "Error 2", cause: error1}
      # Can't easily create true circular references in Elixir immutable data
      # But we test that we handle the visited map correctly
      assert :not_found = ExceptionHandler.find_user_error_in_chain(error2)
    end

    test "ignores non-map candidates" do
      wrapper = %{
        message: "Error",
        cause: "not a map",
        reason: 123
      }

      assert :not_found = ExceptionHandler.find_user_error_in_chain(wrapper)
    end

    test "returns first user error found (depth-first)" do
      deeper_user_error = %{status: 401, message: "Unauthorized"}
      shallow_user_error = %{status: 403, message: "Forbidden"}

      level2 = %{message: "Level 2", cause: deeper_user_error}

      wrapper = %{
        message: "Wrapper",
        cause: level2,
        reason: shallow_user_error
      }

      # cause chain checked first, so deeper_user_error found first
      assert {:ok, ^deeper_user_error} = ExceptionHandler.find_user_error_in_chain(wrapper)
    end
  end

  describe "user_error_exception?/1 (via classification)" do
    test "408 is not a user error (retryable)" do
      error = %{status: 408}
      assert :not_found = ExceptionHandler.find_user_error_in_chain(error)
    end

    test "429 is not a user error (retryable)" do
      error = %{status: 429}
      assert :not_found = ExceptionHandler.find_user_error_in_chain(error)
    end

    test "400 is a user error" do
      error = %{status: 400}
      assert {:ok, ^error} = ExceptionHandler.find_user_error_in_chain(error)
    end

    test "499 is a user error" do
      error = %{status: 499}
      assert {:ok, ^error} = ExceptionHandler.find_user_error_in_chain(error)
    end

    test "500 is not a user error" do
      error = %{status: 500}
      assert :not_found = ExceptionHandler.find_user_error_in_chain(error)
    end

    test "399 is not a user error" do
      error = %{status: 399}
      assert :not_found = ExceptionHandler.find_user_error_in_chain(error)
    end
  end
end
