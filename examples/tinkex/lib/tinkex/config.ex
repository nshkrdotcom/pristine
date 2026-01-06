defmodule Tinkex.Config do
  @moduledoc """
  Client configuration for the Tinkex SDK port.

  Instances of this struct are passed through every API call to support
  multi-tenant usage (different API keys, base URLs, timeouts, and retry policies
  within the same BEAM VM).

  ## Usage

      # From environment (TINKER_API_KEY)
      config = Tinkex.Config.new()

      # With explicit options
      config = Tinkex.Config.new(
        api_key: "tml-your-key",
        base_url: "https://custom.example.com",
        timeout: 30_000,
        max_retries: 5
      )

  ## Parity Mode

  By default, Tinkex uses Python SDK parity values:
    * `timeout: 60_000` (1 minute)
    * `max_retries: 10` (11 total attempts)

  To use BEAM-conservative defaults instead:

      config = Tinkex.Config.new(api_key: "tml-key", parity_mode: :beam)
      # timeout: 120_000, max_retries: 2
  """

  @enforce_keys [:base_url, :api_key]
  defstruct base_url: nil,
            api_key: nil,
            timeout: nil,
            max_retries: nil,
            user_metadata: nil,
            tags: nil,
            telemetry_enabled?: true,
            log_level: nil,
            default_headers: %{},
            default_query: %{},
            http_client: nil

  @type t :: %__MODULE__{
          base_url: String.t(),
          api_key: String.t(),
          timeout: pos_integer(),
          max_retries: non_neg_integer(),
          user_metadata: map() | nil,
          tags: [String.t()] | nil,
          telemetry_enabled?: boolean(),
          log_level: :debug | :info | :warn | :error | nil,
          default_headers: map(),
          default_query: map(),
          http_client: module() | nil
        }

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"

  # BEAM-conservative defaults
  @default_timeout 120_000
  @default_max_retries 2

  # Python SDK parity defaults
  @python_timeout 60_000
  @python_max_retries 10

  @doc """
  Build a config struct using runtime options + environment defaults.

  ## Options

    * `:api_key` - API key (required, or set via TINKER_API_KEY)
    * `:base_url` - Base URL for API (optional, defaults to production)
    * `:timeout` - Request timeout in milliseconds (default: 60_000)
    * `:max_retries` - Number of retry attempts (default: 10)
    * `:user_metadata` - Custom metadata map
    * `:tags` - List of string tags
    * `:telemetry_enabled?` - Enable telemetry (default: true)
    * `:parity_mode` - `:python` (default) or `:beam` for BEAM-conservative defaults
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    parity_mode = Keyword.get(opts, :parity_mode, :python)
    {default_timeout, default_max_retries} = defaults_for_parity(parity_mode)

    api_key =
      pick([
        opts[:api_key],
        Application.get_env(:tinkex, :api_key),
        System.get_env("TINKER_API_KEY")
      ])

    base_url =
      pick(
        [
          opts[:base_url],
          Application.get_env(:tinkex, :base_url),
          System.get_env("TINKER_BASE_URL")
        ],
        @default_base_url
      )

    timeout =
      pick(
        [opts[:timeout], Application.get_env(:tinkex, :timeout)],
        default_timeout
      )

    max_retries =
      pick(
        [opts[:max_retries], Application.get_env(:tinkex, :max_retries)],
        default_max_retries
      )

    tags =
      pick(
        [opts[:tags], Application.get_env(:tinkex, :tags)],
        ["tinkex-elixir"]
      )

    telemetry_enabled? =
      pick(
        [opts[:telemetry_enabled?], Application.get_env(:tinkex, :telemetry_enabled?)],
        true
      )

    log_level =
      pick([opts[:log_level], Application.get_env(:tinkex, :log_level)], nil)

    default_headers =
      pick([opts[:default_headers], Application.get_env(:tinkex, :default_headers)], %{})

    default_query =
      pick([opts[:default_query], Application.get_env(:tinkex, :default_query)], %{})

    config = %__MODULE__{
      base_url: base_url,
      api_key: api_key,
      timeout: timeout,
      max_retries: max_retries,
      user_metadata: opts[:user_metadata],
      tags: tags,
      telemetry_enabled?: telemetry_enabled?,
      log_level: log_level,
      default_headers: default_headers,
      default_query: default_query
    }

    validate!(config)
  end

  @doc """
  Validate an existing config struct. Raises on invalid config.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    validate_api_key!(config.api_key)
    validate_base_url!(config.base_url)
    validate_timeout!(config.timeout)
    validate_max_retries!(config.max_retries)
    config
  end

  @doc """
  Return the default base URL for the Tinker API.
  """
  @spec default_base_url() :: String.t()
  def default_base_url, do: @default_base_url

  @doc """
  Return BEAM-conservative default timeout (120s).
  """
  @spec default_timeout() :: pos_integer()
  def default_timeout, do: @default_timeout

  @doc """
  Return BEAM-conservative default max_retries (2).
  """
  @spec default_max_retries() :: non_neg_integer()
  def default_max_retries, do: @default_max_retries

  @doc """
  Return Python SDK parity timeout (60s).
  """
  @spec python_timeout() :: pos_integer()
  def python_timeout, do: @python_timeout

  @doc """
  Return Python SDK parity max_retries (10).
  """
  @spec python_max_retries() :: non_neg_integer()
  def python_max_retries, do: @python_max_retries

  @doc """
  Mask an API key for safe logging, showing prefix and suffix only.
  """
  @spec mask_api_key(String.t() | nil) :: String.t() | nil
  def mask_api_key(nil), do: nil

  def mask_api_key(api_key) when is_binary(api_key) do
    len = String.length(api_key)

    cond do
      len <= 4 ->
        String.duplicate("*", len)

      true ->
        prefix = String.slice(api_key, 0, min(6, len - 2))
        suffix = String.slice(api_key, -4, 4)
        "#{prefix}...#{suffix}"
    end
  end

  def mask_api_key(other), do: other

  # Private functions

  defp defaults_for_parity(:beam), do: {@default_timeout, @default_max_retries}
  defp defaults_for_parity(:python), do: {@python_timeout, @python_max_retries}
  defp defaults_for_parity(_), do: {@python_timeout, @python_max_retries}

  defp pick(values, default \\ nil) do
    case Enum.find(values, &non_nil?/1) do
      nil -> default
      value -> value
    end
  end

  defp non_nil?(nil), do: false
  defp non_nil?(_), do: true

  defp validate_api_key!(nil) do
    raise ArgumentError,
          "api_key is required. Pass :api_key option or set TINKER_API_KEY env var"
  end

  defp validate_api_key!(api_key) when is_binary(api_key) do
    unless String.starts_with?(api_key, "tml-") do
      raise ArgumentError, "api_key must start with the 'tml-' prefix"
    end

    :ok
  end

  defp validate_api_key!(other) do
    raise ArgumentError, "api_key must be a string, got: #{inspect(other)}"
  end

  defp validate_base_url!(nil) do
    raise ArgumentError, "base_url is required in config"
  end

  defp validate_base_url!(base_url) when is_binary(base_url), do: :ok

  defp validate_base_url!(other) do
    raise ArgumentError, "base_url must be a string, got: #{inspect(other)}"
  end

  defp validate_timeout!(timeout) when is_integer(timeout) and timeout > 0, do: :ok

  defp validate_timeout!(timeout) do
    raise ArgumentError, "timeout must be a positive integer, got: #{inspect(timeout)}"
  end

  defp validate_max_retries!(max_retries) when is_integer(max_retries) and max_retries >= 0,
    do: :ok

  defp validate_max_retries!(max_retries) do
    raise ArgumentError,
          "max_retries must be a non-negative integer, got: #{inspect(max_retries)}"
  end
end

defimpl Inspect, for: Tinkex.Config do
  import Inspect.Algebra

  def inspect(config, opts) do
    data =
      config
      |> Map.from_struct()
      |> Map.update(:api_key, nil, &Tinkex.Config.mask_api_key/1)

    concat(["#Tinkex.Config<", to_doc(data, opts), ">"])
  end
end
