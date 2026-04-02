# OAuth And Token Sources

`Pristine.OAuth2` is the runtime OAuth control plane. It handles authorization
URL generation, token exchange, token refresh, and token persistence over the
runtime transport boundary.

Ownership split:

- `pristine` owns the generic OAuth runtime mechanics
- provider SDK repos own provider URLs, scopes, and provider-local helper
  modules
- higher control planes own durable install records, secret authority, and
  hosted callback routes

## Build A Provider From Security-Scheme Metadata

```elixir
provider =
  Pristine.OAuth2.Provider.from_security_scheme!(
    "oauth",
    %{
      "type" => "oauth2",
      "x-pristine-flow" => "authorizationCode",
      "x-pristine-token-content-type" => "application/x-www-form-urlencoded",
      "flows" => %{
        "authorizationCode" => %{
          "authorizationUrl" => "https://example.com/oauth/authorize",
          "tokenUrl" => "https://example.com/oauth/token",
          "scopes" => %{"read" => "Read access"}
        }
      }
    }
  )
```

## Build An Authorization Request

```elixir
{:ok, authorization_request} =
  Pristine.OAuth2.authorization_request(
    provider,
    client_id: System.fetch_env!("CLIENT_ID"),
    redirect_uri: "http://localhost:4000/callback",
    scopes: ["read"],
    generate_state: true,
    pkce: true
  )
```

## Exchange A Code

OAuth token exchange uses a runtime client context for transport and serializer
selection.

```elixir
client =
  Pristine.Client.new(
    base_url: "https://example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON
  )

{:ok, token} =
  Pristine.OAuth2.exchange_code(
    provider,
    code,
    context: client.context,
    client_id: System.fetch_env!("CLIENT_ID"),
    client_secret: System.fetch_env!("CLIENT_SECRET")
  )
```

## Persisted Tokens

`Pristine.OAuth2.SavedToken` uses `Pristine.OAuth2` directly for refresh flows.
Browser launch and loopback callback capture remain optional adapter seams on
top of the runtime boundary.

That means a provider SDK can expose a thin helper layer over `Pristine.OAuth2`
without reimplementing token persistence or refresh merge behavior.
