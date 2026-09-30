<!-- leaf: implement-hub-domain-1/integrations--part-4 · source: hub-domain-integrations.md -->

# Hub Domain: Integrations — continued (part 4)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `BASE` | module constant, `"/api/integrations"` | fixed | Not injectable; every request path in `integrations.ts` is built as `${BASE}/...`. |
| `OAUTH_CALLBACK_PATH` | module constant, `"/integrations/oauth-callback"` | fixed | The client route the OAuth/app-install redirect lands on; shared by `oauthCallbackUrl` and the callback page. |
| `OAUTH_STATE_TTL_MS` | module constant | `600000` (10 min) | How long a minted `state` is treated as fresh by this client's pre-flight check; mirrors (loosely) the backend's own TTL. |
| `OAUTH_STATE_FUTURE_SKEW_MS` | module constant | `60000` (1 min) | How far ahead of this client's clock an issuer's `iat` may be before this pre-flight treats the state as not-yet-valid. |
| `OAUTH_STATE_CLOCK_GRACE_MS` | module constant | `30000` (30 s) | Added to both bounds of the freshness window so this client's check can only be more permissive than the backend's own, never stricter. |
| `ecosystemId` (caller parameter) | `string` | none — required on nearly every call | The ecosystem every provider-config, connection, and OAuth-start call is scoped to; percent-encoded via `enc` in every path/query use. |
| `providerId` (caller parameter) | `string` | none — required on provider-scoped calls | A catalog provider's id; percent-encoded via `enc`. |
| `configId` / `connectionId` (caller parameter) | `string` | none — required on id-addressed calls | A provider config's or connection's own id/rdid; percent-encoded via `enc`. |
| `body` (varies by call) | `ProviderConfigInput` / `CreateProviderConfigBody` / `TestCredentialsBody` / `ConnectRequest` (six `type`-keyed variants) / `TransferProviderConfigBody` / `RegisterInstanceBody` / `LinkTokenBody` / `SyncSettingsBody` / `AdoptInstallationsBody` | none — required except `createLinkToken`'s, which defaults to `{}` | JSON-serialized verbatim as each `POST`/`PUT`/`PATCH` body; see the matching Behavioral Requirement for the exact shape sent. |

## Deep Linking

| Platform | URL Pattern |
|----------|-------------|
| Web | `/integrations/oauth-callback` (`OAUTH_CALLBACK_PATH`) — the fixed landing route for a provider's OAuth/app-install redirect; `oauthCallbackUrl()` builds the full `redirectUri` as `<window.location.origin><OAUTH_CALLBACK_PATH>`. |

This is a web-sourced component; no Apple or Android route is defined by these two files. A future Apple or
Android port would need its own equivalent redirect-landing registration (a custom URL scheme or an
associated-domains universal link on Apple, an App Link/deep link intent filter on Android) — none of
which exists in this checkout to describe.

## Privacy

- **Data collected**: this module originates no analytics of its own. It transports the provider catalog
  (no end-user data), ecosystem provider configs (OAuth client credentials or a GitHub App's app id/private
  key, secret-masked to `hasSecret` — except the deliverability webhook secret, which is passed through unredacted, see
  **webhook-secret-visibility-after-mint**), and connections (`SafeConnection`, whose secrets are already
  redacted by the backend before this client ever sees them).
- **Storage**: none. `integrationsApi` is a stateless per-call request builder (`no-client-side-cache`,
  `stateless-module`); it holds nothing in memory or on disk beyond the lifetime of a single call.
- **Transmission**: every call carries a bearer credential attached by `@agentic-toolkit/auth/client`
  (`session-refresh-waterfall`), not by this module; a `putProviderConfig`/`createProviderConfig`/
  `updateProviderConfig`/`connect` call also transmits whatever client secret, API key, app password, or
  authorization code the caller supplies, over whatever transport the deployment provides — this module
  configures no TLS or transport-level behavior itself.
- **Retention**: none of the secret material this module handles is retained by this module after the
  response it produced is returned to the caller; retention of the underlying credential is a backend
  concern outside these two files.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/integrations/integrations.ts` and
  `wire.ts` hold the client; `integrationsApi` and the standalone OAuth-state helpers are built entirely on
  `authedJson`/`authedRequest` from `@agentic-toolkit/auth/client` (re-exported through `./http`) and `enc`
  (`encodeURIComponent`) from `./client-helpers`; `index.ts` re-exports both files as the package's public
  surface.
- **SwiftUI**: a Swift port would model each wire row (`ProviderCatalogEntry`, `MaskedProviderConfig`,
  `SafeConnection`, `AuthUrlResult`, and the rest) as a `Codable, Hashable, Sendable` struct, and
  `integrationsApi` as an `actor` or `@MainActor final class` exposing `async throws` functions built on
  `URLSession`. `ConnectRequestBody`'s `type`-discriminated union needs a hand-written `Codable`
  implementation (a Swift `enum` with associated values does not auto-derive to this shape); `decodeOAuthStateClaims`
  ports to a small standalone function using `Data(base64Encoded:)` (after the `-`/`_` → `+`/`/` substitution
  and padding this module performs) plus `JSONDecoder`, deliberately never verifying the HMAC client-side.
- **AppKit / UIKit**: no direct UI dependency exists in this module; a macOS/iOS Hub integrations feature
  would consume the ported client through an injected data-source protocol — the same pattern the sibling
  Hub `EcosystemConfig` topics already use for their own data sources — rather than calling `URLSession`
  from the view layer.
- **Compose**: model the wire rows as Kotlin `data class`es annotated `@Serializable`, and
  `ConnectRequestBody`'s discriminated union as a `sealed class` (a closer structural match to the
  TypeScript union than Swift's enum-with-associated-values); model `integrationsApi` as a class exposing
  `suspend fun` equivalents built on Ktor or OkHttp, with a sealed error type carrying the HTTP status and
  optional code in place of `AuthHttpError`.
- **WinUI 3**: model the wire rows as C# `record`s attributed for `System.Text.Json` (e.g.
  `record MaskedProviderConfig(string Id, string EcosystemId, string ProviderId, string Name, ...)`), and
  `ConnectRequestBody`'s `type`-keyed union as a `JsonPolymorphic`-attributed abstract record hierarchy
  (`System.Text.Json`'s `JsonDerivedType` attributes keyed on the same `type` discriminator string values —
  `oauth`, `api_key`, `app_password`, `plaid_link`, `oauth_instance`, `github_app`); model `integrationsApi`
  as a class exposing `Task<T>`-returning methods built on `HttpClient`, attaching
  `Authorization: Bearer <token>` and refreshing on a `401` with the same one-retry waterfall this module
  inherits from `authedFetch` — this repo has no existing WinUI 3 prior art for that refresh-and-retry
  contract, so it would need to be built alongside the port, not assumed; port `decodeOAuthStateClaims`/
  `isOAuthStateFresh` as a small helper using `Convert.FromBase64String` (after the same `-`/`_` substitution
  and padding) and `System.Text.Json`, never verifying the HMAC client-side; back the provider catalog and
  connections lists with an `ObservableCollection<T>` or an `INotifyPropertyChanged` view-model for a WinUI 3
  `ListView`/`ItemsView`.

