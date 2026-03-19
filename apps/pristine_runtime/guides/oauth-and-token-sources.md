# OAuth and Token Sources

Related guides: `code-generation.md`, `manual-contexts-and-adapters.md`,
`foundation-runtime.md`.

`Pristine.SDK.OAuth2` is the SDK-facing OAuth control plane. It handles
authorization URLs, code exchange, refresh, revoke, and introspection without
forcing provider SDKs to expose runtime internals.

For normal API calls after onboarding, pair OAuth tokens with
`Pristine.Adapters.Auth.OAuth2` and a token source.

## Build a Provider from Security Scheme Metadata

Generated SDKs should derive providers from OpenAPI security schemes:

```elixir
provider =
  Pristine.SDK.OAuth2.Provider.from_security_scheme!(
    "providerOAuth",
    %{
      "type" => "oauth2",
      "flows" => %{
        "authorizationCode" => %{
          "authorizationUrl" => "/oauth/authorize",
          "tokenUrl" => "/oauth/token",
          "scopes" => %{"widgets.read" => "Read widgets"}
        }
      },
      "x-pristine-flow" => "authorizationCode",
      "x-pristine-default-scopes" => ["widgets.read"],
      "x-pristine-token-content-type" => "application/json"
    },
    site: "https://api.example.com"
  )
```

That keeps provider-specific OAuth behavior attached to the same OpenAPI data
that generated SDK modules already use.

## Build the Authorization Request

```elixir
{:ok, request} =
  Pristine.SDK.OAuth2.authorization_request(
    provider,
    client_id: "client-id",
    redirect_uri: "https://example.com/callback",
    generate_state: true,
    pkce: true
  )

request.url
request.state
request.pkce_verifier
```

Use `authorization_request/2` when you want Pristine to generate state and PKCE
material for you. Use `authorize_url/2` when your caller already manages that
input explicitly.

## Exchange the Authorization Code

Control-plane requests need a Pristine runtime context for HTTP transport and
serialization:

```elixir
oauth_context =
  Pristine.context(
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON
  )

{:ok, token} =
  Pristine.SDK.OAuth2.exchange_code(
    provider,
    "auth-code",
    client_id: "client-id",
    client_secret: "client-secret",
    redirect_uri: "https://example.com/callback",
    context: oauth_context
  )
```

`Pristine.SDK.OAuth2` uses the in-tree native OAuth backend by default. Browser
launch and loopback callback capture remain optional adapter seams rather than
required dependencies.

## Persist Tokens

Save a token through a token source:

```elixir
:ok =
  Pristine.OAuth2.SavedToken.save(
    token,
    {Pristine.Adapters.TokenSource.File, path: "/tmp/provider-oauth.json", create_dirs?: true}
  )
```

`Pristine.Adapters.TokenSource.File` writes pretty JSON and applies restrictive
file permissions. It validates the token shape on both read and write.

## Use a Token Source for Bearer Auth

Once persisted, wire the saved token into normal API calls:

```elixir
context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    auth: [
      Pristine.Adapters.Auth.OAuth2.new(
        token_source: {Pristine.Adapters.TokenSource.File, path: "/tmp/provider-oauth.json"}
      )
    ]
  )
```

This keeps control-plane OAuth operations and ordinary bearer-authenticated API
requests separate, while still letting them share the same saved token file.

## Refresh Persisted Tokens Explicitly

`Pristine.OAuth2.SavedToken.refresh/2` loads the saved token, uses its refresh
token, merges rotated fields, and writes the updated token back to the same
source:

```elixir
{:ok, refreshed_token} =
  Pristine.OAuth2.SavedToken.refresh(
    provider,
    token_source: {Pristine.Adapters.TokenSource.File, path: "/tmp/provider-oauth.json"},
    client_id: "client-id",
    client_secret: "client-secret",
    context: oauth_context
  )
```

That merged write preserves an existing refresh token when the provider omits a
replacement one and merges `other_params` metadata from both versions.

## Optional Auto-Refresh Wrapper

If your provider returns reliable `expires_at` values, you can wrap another
token source with `Pristine.Adapters.TokenSource.Refreshable`:

```elixir
refreshable_source =
  {Pristine.Adapters.TokenSource.Refreshable,
   inner_source: {Pristine.Adapters.TokenSource.File, path: "/tmp/provider-oauth.json"},
   provider: provider,
   context: oauth_context,
   client_id: "client-id",
   client_secret: "client-secret",
   refresh_skew_seconds: 30}
```

That wrapper only refreshes tokens that have a real `expires_at` value. If your
provider does not publish trustworthy expiry metadata, stay on the explicit
refresh path instead of pretending transparent refresh is safe.
