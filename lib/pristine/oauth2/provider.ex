defmodule Pristine.OAuth2.Provider do
  @moduledoc """
  Normalized OAuth2 provider configuration.
  """

  alias Pristine.Manifest
  alias Pristine.OAuth2.Error

  defstruct name: nil,
            flow: :authorization_code,
            site: nil,
            authorize_url: nil,
            token_url: nil,
            revocation_url: nil,
            introspection_url: nil,
            scopes: %{},
            default_scopes: [],
            client_auth_method: :basic,
            token_method: :post,
            token_content_type: "application/x-www-form-urlencoded",
            metadata: %{}

  @type t :: %__MODULE__{
          name: String.t() | nil,
          flow: :authorization_code | :client_credentials | :password | :refresh_token,
          site: String.t() | nil,
          authorize_url: String.t() | nil,
          token_url: String.t() | nil,
          revocation_url: String.t() | nil,
          introspection_url: String.t() | nil,
          scopes: map(),
          default_scopes: [String.t()],
          client_auth_method: :basic | :request_body | :none,
          token_method: :get | :post,
          token_content_type: String.t(),
          metadata: map()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @spec from_manifest(Manifest.t(), String.t() | atom()) :: {:ok, t()} | {:error, Error.t()}
  def from_manifest(%Manifest{} = manifest, scheme_name) do
    key = to_string(scheme_name)

    case Map.get(manifest.security_schemes, key) do
      %{"type" => "oauth2", "flows" => flows} = scheme when is_map(flows) ->
        {flow_name, flow} = Enum.at(flows, 0)

        {:ok,
         %__MODULE__{
           name: key,
           flow: normalize_flow(flow_name),
           site: manifest.base_url,
           authorize_url: flow["authorizationUrl"],
           token_url: flow["tokenUrl"],
           revocation_url: scheme["x-pristine-revocation-url"],
           introspection_url: scheme["x-pristine-introspection-url"],
           scopes: flow["scopes"] || %{},
           default_scopes: normalize_scopes(scheme["x-pristine-default-scopes"]),
           client_auth_method:
             normalize_client_auth_method(scheme["x-pristine-client-auth-method"]),
           token_method: normalize_token_method(scheme["x-pristine-token-method"]),
           token_content_type:
             scheme["x-pristine-token-content-type"] || "application/x-www-form-urlencoded",
           metadata: Map.drop(scheme, ["type", "flows"])
         }}

      nil ->
        {:error, Error.new(:unknown_security_scheme, message: "unknown oauth2 scheme #{key}")}

      _other ->
        {:error, Error.new(:invalid_provider, message: "security scheme #{key} is not oauth2")}
    end
  end

  @spec from_manifest!(Manifest.t(), String.t() | atom()) :: t()
  def from_manifest!(%Manifest{} = manifest, scheme_name) do
    case from_manifest(manifest, scheme_name) do
      {:ok, provider} -> provider
      {:error, error} -> raise error
    end
  end

  defp normalize_flow("authorizationCode"), do: :authorization_code
  defp normalize_flow("clientCredentials"), do: :client_credentials
  defp normalize_flow("password"), do: :password
  defp normalize_flow("refreshToken"), do: :refresh_token
  defp normalize_flow(flow) when is_atom(flow), do: flow
  defp normalize_flow(_flow), do: :authorization_code

  defp normalize_client_auth_method("request_body"), do: :request_body
  defp normalize_client_auth_method("none"), do: :none
  defp normalize_client_auth_method(method) when method in [:request_body, :none], do: method
  defp normalize_client_auth_method(_method), do: :basic

  defp normalize_token_method("get"), do: :get
  defp normalize_token_method(method) when method == :get, do: :get
  defp normalize_token_method(_method), do: :post

  defp normalize_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)
  defp normalize_scopes(_scopes), do: []
end
