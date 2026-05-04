defmodule Pristine.GovernedAuthority do
  @moduledoc """
  Authority-materialized HTTP inputs for governed Pristine execution.

  Direct Pristine usage keeps passing explicit base URLs, headers, and auth
  adapters. Governed usage passes this value instead, after a higher authority
  has selected the credential, lease, target, redaction policy, and bounded
  materialized headers for one effect.
  """

  @type header_map :: %{optional(String.t()) => String.t()}

  @type t :: %__MODULE__{
          base_url: String.t(),
          base_url_ref: String.t(),
          authority_ref: String.t() | nil,
          provider_account_ref: String.t() | nil,
          connector_instance_ref: String.t() | nil,
          credential_handle_ref: String.t(),
          credential_ref: String.t(),
          credential_lease_ref: String.t(),
          target_ref: String.t(),
          request_scope_ref: String.t(),
          operation_policy_ref: String.t() | nil,
          header_policy_ref: String.t(),
          redaction_ref: String.t() | nil,
          materialization_ref: String.t() | nil,
          materialization_kind: String.t(),
          bearer_token_ref: String.t() | nil,
          oauth_token_source_ref: String.t() | nil,
          app_token_ref: String.t() | nil,
          installation_token_ref: String.t() | nil,
          user_token_ref: String.t() | nil,
          headers: header_map(),
          credential_headers: header_map(),
          allowed_header_names: [String.t()]
        }

  @materialization_aliases %{
    "bearer" => "bearer",
    "oauth_token_source" => "oauth_token_source",
    "oauth-token-source" => "oauth_token_source",
    "app_token" => "app_token",
    "app-token" => "app_token",
    "installation_token" => "installation_token",
    "installation-token" => "installation_token",
    "user_token" => "user_token",
    "user-token" => "user_token"
  }

  @materialization_ref_fields %{
    "bearer" => :bearer_token_ref,
    "oauth_token_source" => :oauth_token_source_ref,
    "app_token" => :app_token_ref,
    "installation_token" => :installation_token_ref,
    "user_token" => :user_token_ref
  }

  @unmanaged_fields [
    :api_key,
    :auth,
    :bearer,
    :default_auth,
    :default_client,
    :env,
    :middleware,
    :oauth_file,
    :oauth_token_source,
    :request_auth,
    :token_file
  ]

  @enforce_keys [
    :base_url,
    :base_url_ref,
    :credential_handle_ref,
    :credential_ref,
    :credential_lease_ref,
    :target_ref,
    :request_scope_ref,
    :header_policy_ref,
    :materialization_kind,
    :credential_headers
  ]
  defstruct base_url: nil,
            base_url_ref: nil,
            authority_ref: nil,
            provider_account_ref: nil,
            connector_instance_ref: nil,
            credential_handle_ref: nil,
            credential_ref: nil,
            credential_lease_ref: nil,
            target_ref: nil,
            request_scope_ref: nil,
            operation_policy_ref: nil,
            header_policy_ref: nil,
            redaction_ref: nil,
            materialization_ref: nil,
            materialization_kind: nil,
            bearer_token_ref: nil,
            oauth_token_source_ref: nil,
            app_token_ref: nil,
            installation_token_ref: nil,
            user_token_ref: nil,
            headers: %{},
            credential_headers: %{},
            allowed_header_names: []

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = authority) do
    validate!(authority)
  end

  def new!(opts) when is_list(opts) do
    opts
    |> Map.new()
    |> new!()
  end

  def new!(%{} = opts) do
    reject_unmanaged_inputs!(opts)

    materialization_kind =
      opts
      |> required_string!(:materialization_kind)
      |> normalize_materialization_kind!()

    headers = normalize_headers(fetch_value(opts, :headers, %{}))
    credential_headers = normalize_headers(fetch_value(opts, :credential_headers, %{}))
    allowed_header_names = normalize_header_names(fetch_value(opts, :allowed_header_names, []))
    validate_allowed_header_names!(allowed_header_names)
    validate_header_policy!(headers, allowed_header_names)
    validate_header_policy!(credential_headers, allowed_header_names)

    credential_handle_ref =
      required_ref!(opts, :credential_handle_ref, [
        "credential-handle://",
        "urn:credential-handle:"
      ])

    authority = %__MODULE__{
      base_url: required_string!(opts, :base_url),
      base_url_ref: required_ref!(opts, :base_url_ref, ["base-url://"]),
      authority_ref: optional_string(opts, :authority_ref),
      provider_account_ref: optional_string(opts, :provider_account_ref),
      connector_instance_ref: optional_string(opts, :connector_instance_ref),
      credential_handle_ref: credential_handle_ref,
      credential_ref: credential_handle_ref,
      credential_lease_ref: required_ref!(opts, :credential_lease_ref, ["credential-lease://"]),
      target_ref: required_ref!(opts, :target_ref, ["target://"]),
      request_scope_ref: required_ref!(opts, :request_scope_ref, ["request-scope://"]),
      operation_policy_ref: optional_string(opts, :operation_policy_ref),
      header_policy_ref: required_ref!(opts, :header_policy_ref, ["header-policy://"]),
      redaction_ref: optional_string(opts, :redaction_ref),
      materialization_ref: optional_string(opts, :materialization_ref),
      materialization_kind: materialization_kind,
      bearer_token_ref: optional_string(opts, :bearer_token_ref),
      oauth_token_source_ref: optional_string(opts, :oauth_token_source_ref),
      app_token_ref: optional_string(opts, :app_token_ref),
      installation_token_ref: optional_string(opts, :installation_token_ref),
      user_token_ref: optional_string(opts, :user_token_ref),
      headers: headers,
      credential_headers: credential_headers,
      allowed_header_names: allowed_header_names
    }

    validate!(authority)
  end

  defp validate!(%__MODULE__{credential_headers: credential_headers} = authority) do
    if map_size(credential_headers) == 0 do
      raise ArgumentError, "governed authority requires credential_headers"
    end

    validate_materialization_ref!(authority)

    authority
  end

  defp validate_materialization_ref!(%__MODULE__{materialization_kind: kind} = authority) do
    field = Map.fetch!(@materialization_ref_fields, kind)

    if present?(Map.fetch!(authority, field)) do
      :ok
    else
      raise ArgumentError, "governed authority requires #{field}"
    end
  end

  defp normalize_materialization_kind!(kind) do
    case Map.fetch(@materialization_aliases, kind) do
      {:ok, normalized} ->
        normalized

      :error ->
        raise ArgumentError, "governed authority materialization_kind is unsupported"
    end
  end

  defp required_ref!(opts, key, allowed_prefixes) do
    value = required_string!(opts, key)

    if Enum.any?(allowed_prefixes, &String.starts_with?(value, &1)) do
      value
    else
      raise ArgumentError, "governed authority requires #{key} with an allowed ref prefix"
    end
  end

  defp required_string!(opts, key) do
    case optional_string(opts, key) do
      value when is_binary(value) and value != "" ->
        value

      _other ->
        raise ArgumentError, "governed authority requires #{key}"
    end
  end

  defp reject_unmanaged_inputs!(opts) do
    Enum.each(@unmanaged_fields, fn key ->
      if present?(fetch_value(opts, key, nil)) do
        raise ArgumentError, "governed authority rejects unmanaged #{key}"
      end
    end)
  end

  defp optional_string(opts, key) do
    case fetch_value(opts, key, nil) do
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      nil -> nil
      value -> to_string(value)
    end
  end

  defp fetch_value(opts, key, default) when is_map(opts) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(opts, key) -> Map.get(opts, key)
      Map.has_key?(opts, string_key) -> Map.get(opts, string_key)
      true -> default
    end
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {name, value} -> {to_string(name), to_string(value)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    if Enum.all?(headers, &tuple_pair?/1) do
      Map.new(headers, fn {name, value} -> {to_string(name), to_string(value)} end)
    else
      %{}
    end
  end

  defp normalize_headers(_headers), do: %{}

  defp tuple_pair?({_name, _value}), do: true
  defp tuple_pair?(_entry), do: false

  defp normalize_header_names(names) when is_list(names) do
    names
    |> Enum.map(&normalize_header_name/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_header_names(_names), do: []

  defp normalize_header_name(name) do
    name
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp validate_allowed_header_names!([]) do
    raise ArgumentError, "governed authority requires allowed_header_names"
  end

  defp validate_allowed_header_names!(_names), do: :ok

  defp validate_header_policy!(headers, allowed_header_names) do
    headers
    |> Map.keys()
    |> Enum.map(&normalize_header_name/1)
    |> Enum.each(fn header_name ->
      unless header_name in allowed_header_names do
        raise ArgumentError, "governed authority header is not allowed by header_policy_ref"
      end
    end)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(value) when is_map(value), do: map_size(value) > 0
  defp present?(_value), do: true
end

defimpl Inspect, for: Pristine.GovernedAuthority do
  import Inspect.Algebra

  def inspect(authority, opts) do
    rendered =
      authority
      |> Map.from_struct()
      |> Map.put(:credential_headers, redact_headers(authority.credential_headers))
      |> to_doc(opts)

    concat(["#Pristine.GovernedAuthority<", rendered, ">"])
  end

  defp redact_headers(headers) do
    Map.new(headers, fn {name, _value} -> {name, "[REDACTED]"} end)
  end
end
