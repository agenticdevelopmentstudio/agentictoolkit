<!-- leaf: implement-hub-domain-1/integrations--part-3 · source: hub-domain-integrations.md -->

# Hub Domain: Integrations — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/integrations--part-3#<slug>`):

- `auth-url-request-shape` MUST
- `install-url-request-shape` MUST
- `adopt-installations-request-shape` MUST
- `adopt-installations-requires-config-id` MUST
- `adopt-installations-idempotent` MUST
- `register-instance-request-shape` MUST
- `register-instance-config-id-overrides-instance-url` MUST
- `create-link-token-request-shape` MUST
- `oauth-callback-path-fixed` MUST
- `oauth-callback-url-is-origin-relative` MUST
- `decode-state-claims-grammar` MUST
- `decode-state-claims-base64url-json` MUST
- `decode-state-claims-field-validation` MUST
- `decode-state-claims-never-verifies-signature` MUST
- `state-freshness-window` MUST
- `state-freshness-constants` MUST
- `every-identifier-url-encoded` MUST
- `no-client-side-cache` MUST
- `stateless-module` MUST
- `errors-propagate-except-not-found-lookups` MUST
- `secrets-are-write-only` MUST
- `oauth-state-claims-not-authorization` MUST
- `ecosystem-scoping-authorized-server-side` MUST
- `rotate-webhook-secret-requires-caller-confirmation` MUST
- `session-refresh-waterfall` MUST
- `errors-carry-status-and-code` MUST

- **auth-url-request-shape**: `getAuthUrl` MUST send `GET {BASE}/providers/<enc(providerId)>/auth-url` with
  query parameters `ecosystemId` and `redirectUri` always present, and `serviceType`/`scopes` appended only
  when given, and MUST return an `AuthUrlResult` (`{ url, state }`).
- **install-url-request-shape**: `getInstallUrl` MUST send `GET {BASE}/providers/<enc(providerId)>/install-url`
  with query parameter `ecosystemId` always present and `serviceType` appended only when given; it MUST NOT
  send a `redirectUri` or `scopes` parameter — a GitHub App's setup URL is configured on the app at the
  provider, not supplied per request, and its permissions are declared on the app rather than negotiated per
  call.
- **adopt-installations-request-shape**: `adoptInstallations` MUST send `POST {BASE}/providers/<enc(providerId)>/adopt-installations`
  with the given `AdoptInstallationsBody` and MUST return an `AdoptInstallationsResult` (`{ connected, skipped }`).
- **adopt-installations-requires-config-id**: `AdoptInstallationsBody.providerConfigId` MUST be a required
  field; per the source's own comment, the app's identity MUST be read by that id rather than resolved any
  other way, because a resolver that falls through to a platform-global app would surface installations
  belonging to other tenants.
- **adopt-installations-idempotent**: calling `adoptInstallations` a second time for the same saved config
  MUST report an already-connected installation under `skipped` rather than creating a duplicate connection;
  the operation MUST be safe to call more than once.
- **register-instance-request-shape**: `registerInstance` MUST send `POST {BASE}/providers/<enc(providerId)>/register-instance`
  with the given `RegisterInstanceBody` and MUST return a `RegisterInstanceResult` (`{ state, authorizeUrl, clientId }`).
- **register-instance-config-id-overrides-instance-url**: when `RegisterInstanceBody.providerConfigId` is
  set, the per-instance `clientId`/`clientSecret`/`instanceUrl` MUST be sourced from that saved provider-config
  instead of a dynamic per-user app registration, even though `RegisterInstanceBody.instanceUrl` remains a
  required field on the request body and is sent — but ignored on this path.
- **create-link-token-request-shape**: `createLinkToken` MUST send `POST {BASE}/providers/<enc(providerId)>/link-token`
  with the given `LinkTokenBody`, or `{}` when no body is given, and MUST return `{ linkToken }`.

**OAuth callback path and state claims (`OAUTH_CALLBACK_PATH`, `oauthCallbackUrl`,
`decodeOAuthStateClaims`, `isOAuthStateFresh`)**

- **oauth-callback-path-fixed**: `OAUTH_CALLBACK_PATH` MUST be the fixed string `/integrations/oauth-callback`,
  shared by the connect flow that builds a `redirectUri` from it and the callback page that receives the
  provider's redirect, so both agree on the path.
- **oauth-callback-url-is-origin-relative**: `oauthCallbackUrl` MUST return
  `<window.location.origin><OAUTH_CALLBACK_PATH>`; it MUST be called only in a browser context, since it
  reads `window.location` with no guard (a documented, client-only precondition).
- **decode-state-claims-grammar**: `decodeOAuthStateClaims` MUST return `null` for any `state` string that
  has no `.` separator, or whose `.` is the first character, or whose `.` is the last character.
- **decode-state-claims-base64url-json**: `decodeOAuthStateClaims` MUST decode only the substring before the
  `.` as base64url-encoded, fatal-UTF-8-decoded JSON (via the shared `decodeBase64UrlJson` reader), and MUST
  return `null` when that decode fails or produces a non-object value.
- **decode-state-claims-field-validation**: `decodeOAuthStateClaims` MUST return `null` unless the decoded
  object's `customerId`, `providerId`, `serviceType`, and `ecosystemId` are all non-empty strings and its
  `iat` is a finite number; when all five checks pass it MUST return an `IntegrationOAuthStateClaims`
  carrying exactly those five fields.
- **decode-state-claims-never-verifies-signature**: `decodeOAuthStateClaims` MUST NOT verify the signature
  half of `state` — per the source's own comment, it exists only to let this client answer questions like
  `isOAuthStateFresh` locally; every value it recovers MUST still be re-verified by the backend (signature,
  caller identity, ecosystem) before `POST /integrations/connect` persists anything, and a forged `state`
  MUST get the same rejection it would have gotten without this function.
- **state-freshness-window**: `isOAuthStateFresh` MUST return `true` only when `now - claims.iat` is between
  `-(OAUTH_STATE_FUTURE_SKEW_MS + OAUTH_STATE_CLOCK_GRACE_MS)` and `OAUTH_STATE_TTL_MS + OAUTH_STATE_CLOCK_GRACE_MS`
  inclusive, using `now = Date.now()` when the caller does not supply one.
- **state-freshness-constants**: `OAUTH_STATE_TTL_MS` MUST be `600000` (10 minutes), `OAUTH_STATE_FUTURE_SKEW_MS`
  MUST be `60000` (1 minute), and `OAUTH_STATE_CLOCK_GRACE_MS` MUST be `30000` (30 seconds).

**Cross-cutting**

- **every-identifier-url-encoded**: every path-segment identifier this client builds (`ecosystemId`,
  `providerId`, `configId`, `connectionId`) MUST be percent-encoded via `enc` (`encodeURIComponent`, aliased
  in `client-helpers.ts`) before being placed in a URL path.
- **no-client-side-cache**: `integrationsApi` MUST NOT cache or memoize any response; every method issues
  exactly one HTTP request per call.
- **stateless-module**: `integrationsApi` and the standalone exported functions MUST hold no mutable
  module-level state across calls; the only module-level values are the `BASE` string constant and the
  three `OAUTH_STATE_*` numeric constants, all fixed.
- **errors-propagate-except-not-found-lookups**: every `integrationsApi` method MUST let a non-2xx response
  propagate as a thrown `AuthHttpError`, except `getProviderConfig` and `getProviderConfigById`, which MUST
  catch a `404` specifically (via `isNotFound`) and resolve `null` instead.
### Security

This is a security-relevant recipe: it manages OAuth authorization flows, ecosystem-scoped provider
credentials (masked OAuth client secrets and GitHub App private keys), and per-config inbound webhook
secrets.

- **secrets-are-write-only**: `ProviderConfigInputBody.clientSecret` MUST never be echoed back by any read
  operation in this client — `listProviderConfigs`, `getProviderConfig`, and `getProviderConfigById` all
  return `MaskedProviderConfigRow`, whose `hasSecret: boolean` reports only whether a secret is stored,
  never its value.
- **webhook-secret-visibility-after-mint**: `DeliverabilityWebhookRow.secret` is typed `string | null` (`null` means "no secret is stored yet") and is passed through exactly as the backend returns it on every read — `listProviderConfigs`, `getProviderConfig`, `getProviderConfigById`, and `rotateWebhookSecret` alike. Unlike `clientSecret`, which every wire row redacts to `hasSecret: boolean`, this client applies no redaction to the webhook secret; whether a later read carries it in cleartext is decided by the backend, not by this module.
- **oauth-state-claims-not-authorization**: the OAuth `state` this client decodes carries `customerId`,
  `providerId`, `serviceType`, and `ecosystemId` in cleartext (base64url-encoded, not encrypted) with only an
  HMAC signature for integrity; `decodeOAuthStateClaims`'s output MUST NOT be used for any authorization
  decision by a caller of this module — per `decode-state-claims-never-verifies-signature`, it informs a
  pre-flight UI check only, never a write.
- **ecosystem-scoping-authorized-server-side**: every operation in this client that names an `ecosystemId`
  MUST rely on the backend to authorize the caller against it; this client performs no client-side
  ecosystem-membership check, and per the module's own top-of-file comment a caller addressing an ecosystem
  it does not own MUST receive a thrown `AuthHttpError` with status `403`, never a silent success or crash.
- **rotate-webhook-secret-requires-caller-confirmation**: rotating a webhook secret SHOULD NOT be triggered
  without positive caller confirmation, because the immediate invalidation of the previous secret
  (`rotate-webhook-secret-is-destructive`) cannot be undone through this client (see Design Decisions for
  why this is a SHOULD, not a MUST, at this layer).
- **session-refresh-waterfall**: a `401` response to any `integrationsApi` call MUST trigger exactly one
  token refresh and one retried request, inherited unconditionally from the shared `authedFetch`; a second
  `401` on the retried request MUST propagate as a thrown `AuthHttpError` with `status: 401`. This module
  defines no refresh or retry logic of its own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause the call
  to throw `AuthHttpError`, carrying the response's HTTP status and, when the body supplies one, a
  machine-readable `code`.

