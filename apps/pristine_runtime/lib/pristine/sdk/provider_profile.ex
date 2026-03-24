defmodule Pristine.SDK.ProviderProfile do
  @moduledoc """
  Provider-specific runtime profile for shared error normalization and result classification.
  """

  alias Pristine.Adapters.Retry.Foundation, as: FoundationRetry

  @type retry_group_selector :: :all | [String.t()] | nil
  @type status_retry_override :: %{
          optional(:retry?) => boolean(),
          optional(:retry_groups) => retry_group_selector(),
          optional(:telemetry_classification) => atom(),
          optional(:breaker_outcome) => :success | :failure | :ignore,
          optional(:limiter_backoff_ms) => non_neg_integer() | :retry_after
        }

  @type t :: %__MODULE__{
          provider: atom() | String.t(),
          default_retry_group: String.t() | nil,
          retryable_groups: retry_group_selector(),
          transport_retry_groups: retry_group_selector(),
          rate_limit_retry_groups: retry_group_selector(),
          rate_limit_detector: (integer(), map(), term() -> boolean()) | nil,
          status_retry_overrides: %{optional(integer()) => status_retry_override()},
          status_code_map: %{optional(integer()) => atom()},
          body_code_map: %{optional(String.t()) => atom()},
          body_code_fields: [String.t()],
          message_fields: [String.t()],
          request_id_headers: [String.t()],
          body_request_id_fields: [String.t()],
          documentation_url_fields: [String.t()],
          additional_data_fields: [String.t()],
          retry_after_reset_at_headers: [String.t()],
          rate_limit_code: atom(),
          response_error_code: atom(),
          connection_code: atom(),
          validation_code: atom()
        }

  defstruct provider: nil,
            default_retry_group: nil,
            retryable_groups: nil,
            transport_retry_groups: nil,
            rate_limit_retry_groups: nil,
            rate_limit_detector: nil,
            status_retry_overrides: %{},
            status_code_map: %{},
            body_code_map: %{},
            body_code_fields: ["code"],
            message_fields: ["message"],
            request_id_headers: [],
            body_request_id_fields: ["request_id"],
            documentation_url_fields: [],
            additional_data_fields: [],
            retry_after_reset_at_headers: [],
            rate_limit_code: :rate_limited,
            response_error_code: :response_error,
            connection_code: :connection,
            validation_code: :validation

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts), do: opts |> Enum.into(%{}) |> new()

  def new(opts) when is_map(opts) do
    provider = Map.get(opts, :provider) || Map.get(opts, "provider")

    if is_nil(provider) do
      {:error, {:missing_required_option, :provider}}
    else
      {:ok,
       %__MODULE__{
         provider: provider,
         default_retry_group: fetch_string(opts, :default_retry_group),
         retryable_groups:
           normalize_retry_group_selector(
             Map.get(opts, :retryable_groups, Map.get(opts, "retryable_groups"))
           ),
         transport_retry_groups:
           normalize_retry_group_selector(
             Map.get(opts, :transport_retry_groups, Map.get(opts, "transport_retry_groups"))
           ),
         rate_limit_retry_groups:
           normalize_retry_group_selector(
             Map.get(opts, :rate_limit_retry_groups, Map.get(opts, "rate_limit_retry_groups"))
           ),
         rate_limit_detector:
           Map.get(opts, :rate_limit_detector, Map.get(opts, "rate_limit_detector")),
         status_retry_overrides:
           normalize_status_retry_overrides(
             Map.get(opts, :status_retry_overrides, Map.get(opts, "status_retry_overrides", %{}))
           ),
         status_code_map:
           normalize_integer_key_map(
             Map.get(opts, :status_code_map, Map.get(opts, "status_code_map", %{}))
           ),
         body_code_map:
           normalize_string_key_map(
             Map.get(opts, :body_code_map, Map.get(opts, "body_code_map", %{}))
           ),
         body_code_fields:
           normalize_string_list(
             Map.get(opts, :body_code_fields, Map.get(opts, "body_code_fields", ["code"]))
           ),
         message_fields:
           normalize_string_list(
             Map.get(opts, :message_fields, Map.get(opts, "message_fields", ["message"]))
           ),
         request_id_headers:
           normalize_string_list(
             Map.get(opts, :request_id_headers, Map.get(opts, "request_id_headers", []))
           ),
         body_request_id_fields:
           normalize_string_list(
             Map.get(
               opts,
               :body_request_id_fields,
               Map.get(opts, "body_request_id_fields", ["request_id"])
             )
           ),
         documentation_url_fields:
           normalize_string_list(
             Map.get(
               opts,
               :documentation_url_fields,
               Map.get(opts, "documentation_url_fields", [])
             )
           ),
         additional_data_fields:
           normalize_string_list(
             Map.get(opts, :additional_data_fields, Map.get(opts, "additional_data_fields", []))
           ),
         retry_after_reset_at_headers:
           normalize_string_list(
             Map.get(
               opts,
               :retry_after_reset_at_headers,
               Map.get(opts, "retry_after_reset_at_headers", [])
             )
           ),
         rate_limit_code:
           Map.get(opts, :rate_limit_code, Map.get(opts, "rate_limit_code", :rate_limited)),
         response_error_code:
           Map.get(
             opts,
             :response_error_code,
             Map.get(opts, "response_error_code", :response_error)
           ),
         connection_code:
           Map.get(opts, :connection_code, Map.get(opts, "connection_code", :connection)),
         validation_code:
           Map.get(opts, :validation_code, Map.get(opts, "validation_code", :validation))
       }}
    end
  end

  def new(_opts), do: {:error, :invalid_options}

  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, profile} -> profile
      {:error, reason} -> raise ArgumentError, "invalid provider profile: #{inspect(reason)}"
    end
  end

  @spec normalize_headers(map() | list() | term()) :: map()
  def normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} -> {to_string(key), value} end)
  end

  def normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn
      {key, value} -> {to_string(key), value}
      other -> {inspect(other), other}
    end)
  end

  def normalize_headers(_headers), do: %{}

  @spec normalize_body(term()) :: term()
  def normalize_body(nil), do: nil

  def normalize_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> normalize_body(decoded)
      {:error, _reason} -> %{"message" => body}
    end
  end

  def normalize_body(body) when is_map(body) do
    Map.new(body, fn {key, value} -> {to_string(key), value} end)
  end

  def normalize_body(body), do: body

  @spec retry_group(t() | nil, map() | nil) :: String.t() | nil
  def retry_group(%__MODULE__{default_retry_group: default_retry_group}, endpoint) do
    Map.get(endpoint || %{}, :retry) || Map.get(endpoint || %{}, "retry") || default_retry_group
  end

  def retry_group(nil, endpoint) do
    Map.get(endpoint || %{}, :retry) || Map.get(endpoint || %{}, "retry")
  end

  @spec retryable_group?(t() | nil, map() | nil) :: boolean()
  def retryable_group?(%__MODULE__{retryable_groups: nil}, endpoint),
    do: default_retryable?(endpoint)

  def retryable_group?(%__MODULE__{retryable_groups: :all}, _endpoint), do: true

  def retryable_group?(%__MODULE__{retryable_groups: groups} = profile, endpoint)
      when is_list(groups) do
    retry_group(profile, endpoint) in groups
  end

  def retryable_group?(nil, endpoint), do: default_retryable?(endpoint)

  @spec transport_retryable?(t() | nil, map() | nil) :: boolean()
  def transport_retryable?(%__MODULE__{transport_retry_groups: :all}, _endpoint), do: true

  def transport_retryable?(%__MODULE__{transport_retry_groups: nil} = profile, endpoint),
    do: retryable_group?(profile, endpoint)

  def transport_retryable?(%__MODULE__{transport_retry_groups: groups} = profile, endpoint)
      when is_list(groups) do
    retry_group(profile, endpoint) in groups
  end

  def transport_retryable?(nil, _endpoint), do: true

  @spec rate_limit_retryable?(t() | nil, map() | nil) :: boolean()
  def rate_limit_retryable?(%__MODULE__{rate_limit_retry_groups: :all}, _endpoint), do: true

  def rate_limit_retryable?(%__MODULE__{rate_limit_retry_groups: nil} = profile, endpoint),
    do: retryable_group?(profile, endpoint)

  def rate_limit_retryable?(%__MODULE__{rate_limit_retry_groups: groups} = profile, endpoint)
      when is_list(groups) do
    retry_group(profile, endpoint) in groups
  end

  def rate_limit_retryable?(nil, _endpoint), do: true

  @spec status_retry_override(t() | nil, integer() | nil) :: status_retry_override() | nil
  def status_retry_override(%__MODULE__{status_retry_overrides: overrides}, status)
      when is_integer(status) do
    Map.get(overrides, status)
  end

  def status_retry_override(_profile, _status), do: nil

  @spec override_retry?(status_retry_override(), t() | nil, map() | nil) :: boolean()
  def override_retry?(override, profile, endpoint) when is_map(override) do
    cond do
      is_boolean(Map.get(override, :retry?)) ->
        Map.fetch!(override, :retry?)

      match?(:all, Map.get(override, :retry_groups)) ->
        true

      is_list(Map.get(override, :retry_groups)) ->
        retry_group(profile, endpoint) in Map.fetch!(override, :retry_groups)

      true ->
        false
    end
  end

  @spec override_applies?(status_retry_override(), t() | nil, map() | nil) :: boolean()
  def override_applies?(override, profile, endpoint) when is_map(override) do
    cond do
      Map.has_key?(override, :retry?) ->
        true

      match?(:all, Map.get(override, :retry_groups)) ->
        true

      is_list(Map.get(override, :retry_groups)) ->
        retry_group(profile, endpoint) in Map.fetch!(override, :retry_groups)

      true ->
        true
    end
  end

  @spec rate_limited?(t() | nil, integer() | nil, map() | list(), term()) :: boolean()
  def rate_limited?(_profile, 429, _headers, _context_data), do: true

  def rate_limited?(%__MODULE__{rate_limit_detector: detector}, status, headers, context_data)
      when is_function(detector, 3) do
    detector.(status, normalize_headers(headers), context_data)
  end

  def rate_limited?(_profile, _status, _headers, _context_data), do: false

  @spec provider_code(t() | nil, integer() | nil, term(), boolean()) :: atom() | nil
  def provider_code(nil, _status, _body, _rate_limited?), do: nil

  def provider_code(%__MODULE__{} = profile, _status, _body, true), do: profile.rate_limit_code

  def provider_code(%__MODULE__{} = profile, status, body, false) do
    code_from_body(profile, body) ||
      Map.get(profile.status_code_map, status, profile.response_error_code)
  end

  @spec request_id(t() | nil, term(), map() | list()) :: String.t() | nil
  def request_id(nil, _body, _headers), do: nil

  def request_id(%__MODULE__{} = profile, body, headers) do
    normalized_body = normalize_body(body)
    normalized_headers = normalize_headers(headers)

    find_string(normalized_body, profile.body_request_id_fields) ||
      find_header(normalized_headers, profile.request_id_headers)
  end

  @spec documentation_url(t() | nil, term()) :: String.t() | nil
  def documentation_url(nil, _body), do: nil

  def documentation_url(%__MODULE__{} = profile, body) do
    body
    |> normalize_body()
    |> find_string(profile.documentation_url_fields)
  end

  @spec additional_data(t() | nil, term()) :: term()
  def additional_data(nil, _body), do: nil

  def additional_data(%__MODULE__{} = profile, body) do
    normalized_body = normalize_body(body)

    Enum.find_value(profile.additional_data_fields, fn field ->
      case normalized_body do
        %{^field => value} -> value
        _other -> nil
      end
    end)
  end

  @spec message(t() | nil, term()) :: String.t() | nil
  def message(nil, body), do: default_message(body)

  def message(%__MODULE__{} = profile, body) do
    normalized_body = normalize_body(body)
    find_string(normalized_body, profile.message_fields) || default_message(normalized_body)
  end

  @spec retry_after_ms(t() | nil, map() | list()) :: non_neg_integer() | nil
  def retry_after_ms(nil, headers), do: FoundationRetry.parse_retry_after(headers)

  def retry_after_ms(%__MODULE__{} = profile, headers) do
    FoundationRetry.parse_retry_after(
      headers,
      reset_at_headers: profile.retry_after_reset_at_headers
    )
  end

  @spec connection_code(t() | nil) :: atom() | nil
  def connection_code(%__MODULE__{} = profile), do: profile.connection_code
  def connection_code(_profile), do: nil

  @spec validation_code(t() | nil) :: atom() | nil
  def validation_code(%__MODULE__{} = profile), do: profile.validation_code
  def validation_code(_profile), do: nil

  @spec header_value(map() | list(), String.t()) :: String.t() | nil
  def header_value(headers, name) when is_map(headers) do
    downcased_name = String.downcase(name)

    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == downcased_name and is_binary(value), do: value
    end)
  end

  def header_value(headers, name) when is_list(headers) do
    downcased_name = String.downcase(name)

    Enum.find_value(headers, fn
      {key, value} when is_binary(value) ->
        if String.downcase(to_string(key)) == downcased_name, do: value

      _other ->
        nil
    end)
  end

  def header_value(_headers, _name), do: nil

  defp code_from_body(%__MODULE__{} = profile, body) do
    normalized_body = normalize_body(body)

    Enum.find_value(profile.body_code_fields, fn field ->
      case normalized_body do
        %{^field => code} when is_binary(code) -> Map.get(profile.body_code_map, code)
        _other -> nil
      end
    end)
  end

  defp find_string(body, fields) when is_map(body) and is_list(fields) do
    Enum.find_value(fields, fn field ->
      case body do
        %{^field => value} when is_binary(value) -> value
        _other -> nil
      end
    end)
  end

  defp find_string(_body, _fields), do: nil

  defp find_header(headers, names) when is_map(headers) and is_list(names) do
    Enum.find_value(names, &header_value(headers, &1))
  end

  defp find_header(_headers, _names), do: nil

  defp default_message(%{"message" => message}) when is_binary(message), do: message
  defp default_message(_body), do: nil

  defp default_retryable?(endpoint) do
    method = Map.get(endpoint || %{}, :method) || Map.get(endpoint || %{}, "method")

    idempotent? =
      Map.get(endpoint || %{}, :idempotency) || Map.get(endpoint || %{}, "idempotency") == true

    idempotent? or safe_method?(method)
  end

  defp safe_method?(method) when is_atom(method),
    do: method in [:delete, :get, :head, :options, :put, :trace]

  defp safe_method?(method) when is_binary(method) do
    method
    |> String.downcase()
    |> String.to_existing_atom()
    |> safe_method?()
  rescue
    ArgumentError -> false
  end

  defp safe_method?(_method), do: false

  defp fetch_string(opts, key) do
    case Map.get(opts, key) || Map.get(opts, Atom.to_string(key)) do
      value when is_binary(value) -> value
      _other -> nil
    end
  end

  defp normalize_retry_group_selector(:all), do: :all
  defp normalize_retry_group_selector(nil), do: nil

  defp normalize_retry_group_selector(groups) when is_list(groups),
    do: normalize_string_list(groups)

  defp normalize_retry_group_selector(_groups), do: nil

  defp normalize_status_retry_overrides(overrides) when is_map(overrides) do
    Map.new(overrides, fn {status, override} ->
      {normalize_integer_key(status), normalize_status_retry_override(override)}
    end)
  end

  defp normalize_status_retry_overrides(_overrides), do: %{}

  defp normalize_status_retry_override(override) when is_map(override) do
    override
    |> Map.new(fn {key, value} ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> atom
          binary when is_binary(binary) -> String.to_atom(binary)
        end

      normalized_value =
        case normalized_key do
          :retry_groups -> normalize_retry_group_selector(value)
          _other -> value
        end

      {normalized_key, normalized_value}
    end)
  end

  defp normalize_status_retry_override(_override), do: %{}

  defp normalize_integer_key_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {normalize_integer_key(key), value} end)
  end

  defp normalize_integer_key_map(_map), do: %{}

  defp normalize_integer_key(key) when is_integer(key), do: key

  defp normalize_integer_key(key) when is_binary(key) do
    case Integer.parse(key) do
      {integer, _rest} -> integer
      _other -> key
    end
  end

  defp normalize_integer_key(key), do: key

  defp normalize_string_key_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_string_key_map(_map), do: %{}

  defp normalize_string_list(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_string_list(_list), do: []
end
