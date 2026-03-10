defmodule Pristine.OpenAPI.Client do
  @moduledoc """
  Placeholder request contract for `oapi_generator` output that targets Pristine.

  The initial bridge keeps the generated operation surface stable while the
  downstream runtime mapping is fleshed out in later phases.
  """

  @type response_type :: term()

  @type request_t :: %{
          required(:args) => keyword(),
          required(:call) => {module(), atom()},
          required(:method) => atom(),
          required(:opts) => keyword(),
          required(:url) => String.t(),
          optional(:body) => term(),
          optional(:query) => keyword(),
          optional(:request) => [{String.t(), response_type()}],
          optional(:response) => [{integer() | :default, response_type()}]
        }

  @spec request(request_t()) :: {:ok, request_t()}
  def request(request) when is_map(request), do: {:ok, request}
end
