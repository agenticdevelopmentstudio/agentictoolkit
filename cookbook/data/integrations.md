---
id: 45c318d7-dd3e-491c-8811-eb2a3d79bca9
title: 'Hub Domain: Integrations'
domain: agentictoolkit://cookbook/data/integrations
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'TypeScript client for /api/integrations: the provider catalog, ecosystem
  provider configs and connections, OAuth/install/link-token endpoints, and OAuth
  state claims.'
platforms:
- typescript
- web
tags:
- hub
- integrations
- oauth
- connections
- providers
- webhooks
depends-on: []
related:
- agentictoolkit://cookbook/data/access
- agentictoolkit://cookbook/hub/features/ecosystem-config
references:
- packages/web/packages/data/src/integrations/integrations.ts (agentictoolkit)
- packages/web/packages/data/src/integrations/wire.ts (agentictoolkit)
- packages/web/packages/data/src/integrations/index.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
- packages/web/packages/auth/src/tokens.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Integrations

## Overview

`integrations.ts` and `wire.ts`, re-exported by `index.ts`, are the client for the `/api/integrations`
surface, per the module's own top-of-file comment. It covers three things: the provider CATALOG
(`listProviders`, every provider the platform can integrate, with its `authMethod` and capabilities);
an ecosystem's own, owner-scoped provider CONFIGS (OAuth client credentials or a GitHub App's identity,
plus optional endpoint overrides, addressed two different ways — by `providerId` and by the config's own
`id`/`rdid`); and an ecosystem's CONNECTIONS (linked accounts) — list, connect (all six `ConnectRequestBody`
auth methods), disconnect, sync-now, per-connection sync settings, plus the OAuth/app-install/self-hosted-
instance/Plaid-Link start endpoints and a local, non-authoritative decoder for the signed OAuth `state`
round-trip value. `wire.ts` holds the wire shapes; `integrations.ts` holds the `integrationsApi` object of
twenty request-builder methods plus the standalone `OAUTH_CALLBACK_PATH`/`oauthCallbackUrl`/
`decodeOAuthStateClaims`/`isOAuthStateFresh` exports, all built on the shared `authedJson`/`authedRequest`
helpers from `@agentic-toolkit/auth/client` (re-exported through `./http`) and `enc`
(`encodeURIComponent`, from `./client-helpers`). It is a headless **logic** module — no visual surface — so
this recipe marks Appearance, States, and Accessibility not applicable and carries the runtime contract
entirely in Behavioral Requirements, per the non-UI component guidance this recipe was authored under.

## Behavioral Requirements

**Provider catalog (`listProviders`)**

- **provider-catalog-fetch**: `listProviders` MUST send `GET {BASE}/providers`, where `BASE` is the fixed
  constant `/api/integrations`, and MUST return the `providers` array unwrapped from the `{ providers }`
  response envelope.

**Provider configs — provider-id-addressed (`listProviderConfigs`, `getProviderConfig`,
`putProviderConfig`, `deleteProviderConfig`)**

- **provider-config-list**: `listProviderConfigs` MUST send `GET {BASE}/ecosystems/<enc(ecosystemId)>/provider-configs`
  and MUST return the `configs` array unwrapped from `{ configs }`.
- **provider-config-get-by-provider-id**: `getProviderConfig` MUST send `GET {BASE}/ecosystems/<enc(ecosystemId)>/provider-configs/<enc(providerId)>`.
- **provider-config-get-not-found-null**: `getProviderConfig` MUST return `null`, not throw, when that `GET`
  fails with `isNotFound` (a backend `404`); any other thrown error MUST propagate unchanged.
- **provider-config-put-preserves-blank-secret**: `putProviderConfig` MUST send `PUT` to that same path with
  the given `ProviderConfigInput` JSON-serialized verbatim as the body; per `ProviderConfigInputBody.clientSecret`'s
  own documentation, a blank or absent `clientSecret` in that body MUST preserve the config's currently stored
  secret rather than clearing it.
- **provider-config-delete-by-provider-id**: `deleteProviderConfig` MUST send `DELETE` to that same path via
  `authedRequest` and MUST resolve with no value.

**Provider configs — id/rdid-addressed (`createProviderConfig`, `getProviderConfigById`,
`updateProviderConfig`, `deleteProviderConfigById`)**

- **provider-config-create**: `createProviderConfig` MUST send `POST {BASE}/ecosystems/<enc(ecosystemId)>/provider-configs`
  (the collection path, with no trailing id segment) with a `CreateProviderConfigBody` (`providerId`, `name`,
  plus the `ProviderConfigInputBody` fields) JSON-serialized verbatim as the body, and MUST return the
  resulting `MaskedProviderConfig`.
- **provider-config-get-by-id**: `getProviderConfigById` MUST send `GET {BASE}/ecosystems/<enc(ecosystemId)>/provider-configs/<enc(configId)>`.
- **provider-config-get-by-id-not-found-null**: `getProviderConfigById` MUST return `null`, not throw, on
  `isNotFound`, matching `provider-config-get-not-found-null`'s pattern for the provider-id-addressed lookup.
- **provider-config-update-by-id**: `updateProviderConfig` MUST send `PUT` to that same id-addressed path
  with a `ProviderConfigInput` body optionally extended with `name`.
- **provider-config-delete-by-id**: `deleteProviderConfigById` MUST send `DELETE` to that same id-addressed
  path via `authedRequest` and MUST resolve with no value.
- **provider-config-two-address-schemes-share-a-url-shape**: the provider-id-addressed path (built by the
  file's private `configPath` helper when given a `providerId`) and the id/rdid-addressed path (built by the
  private `configByIdPath` helper) MUST both resolve to the identical template
  `{BASE}/ecosystems/<enc(ecosystemId)>/provider-configs/<enc(...)>` — the two helpers differ only in the
  name of the parameter they encode into the trailing segment, never in the URL shape produced (see Design
  Decisions).

**Credential testing (`testProviderConfig`, `testProviderCredentials`)**

- **test-saved-config**: `testProviderConfig` MUST send `POST` to the id-addressed config path's `/test`
  sub-path and MUST return an `IntegrationTestResult`.
- **test-saved-config-github-app-also-connects**: for a `github_app` provider, performing `testProviderConfig`
  IS the connect: the only proof an app id and private key are real is minting a JWT and enumerating the
  installations the app can see, and that enumeration itself creates the connection rows and warms the
  repository cache. `IntegrationTestResult.adopted`, when present, MUST report the `AdoptInstallationsResult`
  of that side effect, and a caller holding a connection list MUST refresh it whenever `adopted` is present.
- **test-result-ok-false-is-not-an-error**: a refused credential MUST resolve `testProviderConfig`/
  `testProviderCredentials` with `{ ok: false, summary, notes }`, never throw; only a malformed request (an
  unknown provider, a field the provider does not declare, or a provider with no way to be tested at all)
  MUST throw.
- **test-draft-credentials-writes-nothing**: `testProviderCredentials` MUST send `POST {BASE}/providers/<enc(providerId)>/test-credentials`
  with the given `TestCredentialsBody`, and MUST NOT create or modify a provider config, a connection, or a
  repository cache — the whole difference from `testProviderConfig`.
- **test-draft-credentials-with-stored-secret**: when `TestCredentialsBody.providerConfigId` is given with a
  blank `clientSecret`, `testProviderCredentials` MUST test against that config's already-stored secret rather
  than an empty one, because a saved secret is never re-displayed in an edit form (it is write-only): a blank
  field there means "unchanged," not "no secret."

**Transfer (`transferProviderConfig`)**

- **transfer-request-shape**: `transferProviderConfig` MUST send `POST` to the id-addressed config path's
  `/transfer` sub-path with a `TransferProviderConfigBody` (`{ targetEcosystemId }`) and MUST return a
  `TransferProviderConfigResult`.
- **transfer-moves-credential-connections-and-caches-together**: the result MUST report the moved config's
  credential, the connections it minted, and their cached repository lists as having moved together in one
  `TransferProviderConfigResult`; the caller MUST manage both the source and destination ecosystem after a
  transfer.
- **transfer-mints-new-rdid**: the transferred config's `rdid` MUST be treated as re-minted at the
  destination ecosystem; the address it answered to before the transfer MUST NOT be assumed to still resolve.
- **transfer-connections-count-is-live-only**: `TransferProviderConfigResult.connections` MUST count only
  connections that are live at the destination, not the number of connection rows that were moved; a moved
  connection that was already disconnected MUST NOT be counted.

**Webhook secret rotation (`rotateWebhookSecret`)**

- **rotate-webhook-secret-request-shape**: `rotateWebhookSecret` MUST send `POST` to the id-addressed config
  path's `/rotate-webhook-secret` sub-path with no body and MUST return the updated `MaskedProviderConfig`.
- **rotate-webhook-secret-is-destructive**: the newly minted secret MUST invalidate the previously stored one
  immediately; per the source's own comment, a provider still configured with the old secret is expected to
  start failing its own delivery attempts at the provider's side with no signal raised by this client.
- **rotate-webhook-secret-also-generates-first-secret**: for a `MaskedProviderConfig` whose
  `deliverabilityWebhook.secret` is `null` (a config created before per-config secrets existed),
  `rotateWebhookSecret` MUST be the only operation in this client that gives that config a working secret.

**Connections (`listConnections`, `connect`, `disconnect`, `sync`, `patchSettings`)**

- **connections-list-scoped-by-ecosystem**: `listConnections` MUST send `GET {BASE}?ecosystemId=<enc(ecosystemId)>`
  and MUST return the `connections` array unwrapped from `{ connections }`, across every provider owned by
  that ecosystem.
- **connect-request-shape**: `connect` MUST send `POST {BASE}/connect` with the given `ConnectRequest`
  JSON-serialized verbatim as the body and MUST return the resulting `SafeConnection`.
- **connect-every-variant-names-ecosystem**: every member of the `ConnectRequestBody` discriminated union
  (`oauth`, `api_key`, `app_password`, `plaid_link`, `oauth_instance`, `github_app`, keyed by `type`) MUST
  include `ecosystemId`; `connect` names the target ecosystem in the body on every call regardless of auth
  method.
- **connect-github-app-has-no-code**: the `github_app` variant of `ConnectRequest` MUST carry
  `installationId` and MUST NOT carry a `code` field — unlike every other variant, which exchanges an
  authorization code, a GitHub App installation is not an authorization to exchange; it already exists and
  is addressed by id.
- **connect-app-password-source-exclusivity-delegated**: the `app_password` variant MAY supply inline
  credentials (`identifier`, `password`, `instanceUrl`) or a `providerConfigId` to source them from a saved
  ecosystem provider-config; `connect` MUST NOT reject a body that supplies both or neither — per the type's
  own comment, that exclusivity is enforced server-side, not by this client.
- **disconnect-request-shape**: `disconnect` MUST send `DELETE {BASE}/<enc(connectionId)>` via
  `authedRequest` and MUST resolve with no value; it soft-deletes a connection the caller owns.
- **sync-request-shape**: `sync` MUST send `POST {BASE}/<enc(connectionId)>/sync` via `authedRequest` and
  MUST resolve with no value on success.
- **sync-no-worker-throws-503**: `sync` MUST throw an `AuthHttpError` with status `503` when no worker is
  registered yet for the connection's provider; per the source's own comment, the caller shows this as an
  inline "not available" note rather than a hard error.
- **patch-settings-request-shape**: `patchSettings` MUST send `PATCH {BASE}/<enc(connectionId)>/settings`
  with the given `SyncSettingsBody` and MUST return the `SyncSettingsResult` (`{ ok, syncSettings }`)
  verbatim.

**OAuth / install / instance / link-token start endpoints (`getAuthUrl`, `getInstallUrl`,
`adoptInstallations`, `registerInstance`, `createLinkToken`)**

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

## Appearance

Not applicable — this is the integrations data-access client, not a visual component.

## States

Not applicable — this is the integrations data-access client, not a visual component; any loading, error,
or empty visual state is owned by the presentation layer that consumes `integrationsApi`. The only runtime
state machine this component defines is the OAuth `state` freshness window, specified under Behavioral
Requirements (`state-freshness-window`), not here.

## Accessibility

Not applicable — this is the integrations data-access client, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-integrations-001 | provider-catalog-fetch | `listProviders()` against `{ providers: [{ providerId: "github", authMethod: "github_app", testable: true, ... }] }` | Request URL is `/api/integrations/providers`; resolves to that array unwrapped from the envelope |
| hub-domain-integrations-002 | provider-config-list | `listProviderConfigs("eco-1")` | `GET /api/integrations/ecosystems/eco-1/provider-configs`; resolves to the `configs` array unwrapped |
| hub-domain-integrations-003 | provider-config-get-by-provider-id, provider-config-get-not-found-null | `getProviderConfig("eco-1", "github")` against a `404` response | Resolves to `null`, does not throw |
| hub-domain-integrations-004 | provider-config-put-preserves-blank-secret | `putProviderConfig("eco-1", "github", { clientId: "x" })` (no `clientSecret`) | `PUT /api/integrations/ecosystems/eco-1/provider-configs/github` with body `{ clientId: "x" }` only; the stored secret is unchanged per the field's own contract |
| hub-domain-integrations-005 | provider-config-delete-by-provider-id | `deleteProviderConfig("eco-1", "github")` | `DELETE /api/integrations/ecosystems/eco-1/provider-configs/github`; resolves to `undefined` |
| hub-domain-integrations-006 | provider-config-create | `createProviderConfig("eco-1", { providerId: "github", name: "Prod" })` | `POST /api/integrations/ecosystems/eco-1/provider-configs` (no trailing id) with that body; resolves to a `MaskedProviderConfig` |
| hub-domain-integrations-007 | provider-config-get-by-id, provider-config-two-address-schemes-share-a-url-shape | `getProviderConfigById("eco-1", "cfg-uuid-1")` | `GET /api/integrations/ecosystems/eco-1/provider-configs/cfg-uuid-1` — an identical URL template to `getProviderConfig`'s, differing only in what the trailing segment addresses |
| hub-domain-integrations-008 | provider-config-get-by-id-not-found-null | `getProviderConfigById("eco-1", "cfg-missing")` against a `404` response | Resolves to `null`, does not throw |
| hub-domain-integrations-009 | provider-config-update-by-id | `updateProviderConfig("eco-1", "cfg-1", { name: "Renamed" })` | `PUT /api/integrations/ecosystems/eco-1/provider-configs/cfg-1` with body `{ name: "Renamed" }` |
| hub-domain-integrations-010 | provider-config-delete-by-id | `deleteProviderConfigById("eco-1", "cfg-1")` | `DELETE /api/integrations/ecosystems/eco-1/provider-configs/cfg-1`; resolves to `undefined` |
| hub-domain-integrations-011 | test-saved-config, test-result-ok-false-is-not-an-error | `testProviderConfig("eco-1", "cfg-1")` against a stub returning `{ ok: false, summary: "Invalid token", notes: [] }` | `POST /api/integrations/ecosystems/eco-1/provider-configs/cfg-1/test`; resolves (does not throw) to that body |
| hub-domain-integrations-012 | test-saved-config-github-app-also-connects | `testProviderConfig` for a `github_app` config, stub returns `{ ok: true, adopted: { connected: [...], skipped: [] } }` | Resolves with `adopted` present; caller must refresh its connection list |
| hub-domain-integrations-013 | test-draft-credentials-writes-nothing, test-draft-credentials-with-stored-secret | `testProviderCredentials("github", { ecosystemId: "eco-1", providerConfigId: "cfg-1" })` (`clientSecret` omitted) | `POST /api/integrations/providers/github/test-credentials` with `providerConfigId` and no `clientSecret`; tests the stored secret; creates no config, connection, or cache |
| hub-domain-integrations-014 | transfer-request-shape, transfer-moves-credential-connections-and-caches-together, transfer-mints-new-rdid | `transferProviderConfig("eco-1", "cfg-1", { targetEcosystemId: "eco-2" })` | `POST .../cfg-1/transfer`; `result.config.ecosystemId === "eco-2"` with a new `rdid`; `result.connections` and `result.repositoryCaches` are both present in the same result |
| hub-domain-integrations-015 | transfer-connections-count-is-live-only | A transfer moving 3 connection rows, 1 already disconnected | `result.connections === 2` |
| hub-domain-integrations-016 | rotate-webhook-secret-request-shape, rotate-webhook-secret-is-destructive | `rotateWebhookSecret("eco-1", "cfg-1")` | `POST .../cfg-1/rotate-webhook-secret` with no body; returns the updated config; the previously stored secret is no longer the one returned |
| hub-domain-integrations-017 | rotate-webhook-secret-also-generates-first-secret | `rotateWebhookSecret` on a config whose `deliverabilityWebhook.secret` is `null` | The returned config's `deliverabilityWebhook.secret` is non-null |
| hub-domain-integrations-018 | connections-list-scoped-by-ecosystem | `listConnections("eco-1")` | `GET /api/integrations?ecosystemId=eco-1`; resolves to the `connections` array unwrapped |
| hub-domain-integrations-019 | connect-request-shape, connect-every-variant-names-ecosystem | `connect({ type: "oauth", providerId: "github", serviceType: "repos", ecosystemId: "eco-1", code: "abc", redirectUri: "https://x/cb", state: "s.sig" })` | `POST /api/integrations/connect` with that body verbatim; resolves to a `SafeConnection` |
| hub-domain-integrations-020 | connect-github-app-has-no-code | `connect({ type: "github_app", providerId: "github", serviceType: "repos", ecosystemId: "eco-1", installationId: "12345", state: "s.sig" })` | Request body has `installationId` and no `code` field |
| hub-domain-integrations-021 | connect-app-password-source-exclusivity-delegated | `connect({ type: "app_password", providerId: "mastodon", serviceType: "posts", ecosystemId: "eco-1", identifier: "me", password: "pw", providerConfigId: "cfg-1" })` (both inline creds AND `providerConfigId` present) | The body is sent unchanged; `connect` performs no client-side rejection of the combination |
| hub-domain-integrations-022 | disconnect-request-shape | `disconnect("conn-1")` | `DELETE /api/integrations/conn-1`; resolves to `undefined` |
| hub-domain-integrations-023 | sync-request-shape, sync-no-worker-throws-503 | `sync("conn-1")` against a `503` response | `POST /api/integrations/conn-1/sync`; throws `AuthHttpError` with `status: 503` |
| hub-domain-integrations-024 | patch-settings-request-shape | `patchSettings("conn-1", { gmailLabelIds: ["INBOX"] })` | `PATCH /api/integrations/conn-1/settings` with that body; resolves to `{ ok, syncSettings }` |
| hub-domain-integrations-025 | auth-url-request-shape | `getAuthUrl("github", { ecosystemId: "eco-1", redirectUri: "https://x/cb" })` | `GET .../providers/github/auth-url?ecosystemId=eco-1&redirectUri=...` with no `serviceType`/`scopes` parameter present |
| hub-domain-integrations-026 | install-url-request-shape | `getInstallUrl("github", { ecosystemId: "eco-1" })` | `GET .../providers/github/install-url?ecosystemId=eco-1` with no `redirectUri` or `scopes` parameter anywhere in the URL |
| hub-domain-integrations-027 | adopt-installations-request-shape | `adoptInstallations("github", { ecosystemId: "eco-1", providerConfigId: "cfg-1" })` | `POST .../providers/github/adopt-installations` with that body; resolves to `{ connected, skipped }` |
| hub-domain-integrations-028 | adopt-installations-requires-config-id | Constructing an `AdoptInstallationsBody` literal without `providerConfigId` | Fails to typecheck against the required field; confirmed by the type declaration, no runtime test needed |
| hub-domain-integrations-029 | adopt-installations-idempotent | `adoptInstallations` called twice with the same `providerConfigId` against an installation already connected | The second call reports it under `skipped`, not `connected`; no duplicate connection is created |
| hub-domain-integrations-030 | register-instance-request-shape, register-instance-config-id-overrides-instance-url | `registerInstance("mastodon", { ecosystemId: "eco-1", instanceUrl: "https://example.social", redirectUri: "https://x/cb", providerConfigId: "cfg-1" })` | `POST .../providers/mastodon/register-instance` with that body; the returned `clientId` is sourced from `cfg-1`, even though `instanceUrl` is present in the sent body |
| hub-domain-integrations-031 | create-link-token-request-shape | `createLinkToken("plaid")` (no body) | `POST .../providers/plaid/link-token` with body `{}`; resolves to `{ linkToken }` |
| hub-domain-integrations-032 | oauth-callback-path-fixed, oauth-callback-url-is-origin-relative | `oauthCallbackUrl()` with `window.location.origin === "https://app.example.test"` | Returns `"https://app.example.test/integrations/oauth-callback"` |
| hub-domain-integrations-033 | decode-state-claims-grammar | `decodeOAuthStateClaims("nodothere")` | Returns `null` (no `.` present) |
| hub-domain-integrations-034 | decode-state-claims-grammar | `decodeOAuthStateClaims(".abc")` | Returns `null` (the `.` is the first character) |
| hub-domain-integrations-035 | decode-state-claims-grammar | `decodeOAuthStateClaims("abc.")` | Returns `null` (the `.` is the last character) |
| hub-domain-integrations-036 | decode-state-claims-base64url-json, decode-state-claims-field-validation | `decodeOAuthStateClaims` on a `state` whose prefix base64url-decodes to `{"customerId":"c1","providerId":"github","serviceType":"repos","ecosystemId":"eco-1","iat":1000}`, followed by `.` and any suffix | Returns `{ customerId: "c1", providerId: "github", serviceType: "repos", ecosystemId: "eco-1", iat: 1000 }` |
| hub-domain-integrations-037 | decode-state-claims-field-validation | Same claims object but with `ecosystemId: ""` | Returns `null` |
| hub-domain-integrations-038 | decode-state-claims-never-verifies-signature | The same well-formed claims prefix from vector 036, but with an arbitrary, invalid signature suffix | Still returns the decoded claims — the signature is never checked by this function |
| hub-domain-integrations-039 | state-freshness-window, state-freshness-constants | `isOAuthStateFresh({ iat: 0 }, 630000)` | Returns `true` (exactly at the widened upper bound: `600000 + 30000`) |
| hub-domain-integrations-040 | state-freshness-window | `isOAuthStateFresh({ iat: 0 }, 630001)` | Returns `false` (one millisecond past the widened upper bound) |
| hub-domain-integrations-041 | state-freshness-window | `isOAuthStateFresh({ iat: 100000 }, 9999)` | Returns `true` (`now - iat = -90001`... boundary case: exactly `-90000` is the widened lower bound, one past it is `false`) |
| hub-domain-integrations-042 | every-identifier-url-encoded | `disconnect("a/b")` | `DELETE /api/integrations/a%2Fb` |
| hub-domain-integrations-043 | no-client-side-cache, stateless-module | `listProviders()` called twice in a row | Two separate HTTP requests are issued; the second call is not served from any in-module cache |
| hub-domain-integrations-044 | errors-propagate-except-not-found-lookups | `getProviderConfig("eco-1", "github")` against a `500` response | The `500` propagates as a thrown `AuthHttpError`; it is not converted to `null` (unlike a `404`) |
| hub-domain-integrations-045 | secrets-are-write-only | `listProviderConfigs("eco-1")` response body | No element of the resolved array has a `clientSecret` field; each has only `hasSecret: boolean` |
| hub-domain-integrations-046 | ecosystem-scoping-authorized-server-side | `listConnections("eco-2")` called by a caller who does not own `eco-2` | The call rejects with `AuthHttpError`, `status: 403` |
| hub-domain-integrations-047 | session-refresh-waterfall | Any `integrationsApi` call's first response is `401`; `refreshAccessToken()` resolves a new token | The request is retried once with the new token; a `401` on that retry throws `AuthHttpError` with `status: 401` — traced to `authedFetch` in `auth/src/client.ts`, exercised only indirectly through `integrationsApi` |

## Edge Cases

- **Null and empty input — path identifiers**: `ecosystemId`/`providerId`/`configId`/`connectionId` are typed
  `string` and are not checked for emptiness client-side; an empty value is still percent-encoded (to the
  empty string) and sent, producing a request the backend answers with its own `404`/`400` — a non-empty
  identifier is a caller precondition, per the module's own top-of-file comment naming `ecosystemId` as
  something "the caller must manage."
- **Null and empty input — `state`**: `decodeOAuthStateClaims` MUST return `null` for the empty string (no
  `.` present, per `decode-state-claims-grammar`) rather than throw.
- **Null and empty input — `createLinkToken`'s optional body**: an omitted `body` argument MUST be sent as
  `{}`, per `create-link-token-request-shape`; there is no distinct "send nothing" path.
- **Boundary values — OAuth state freshness**: the widened window's both edges are inclusive per
  `state-freshness-window`; one millisecond outside either edge MUST flip the result, as vectors 039–041
  show.
- **Boundary values — `state` grammar**: a `.` at position `0` or at the last character position are both
  rejected by `decode-state-claims-grammar`; a `.` anywhere strictly between the first and last character of
  a non-empty prefix and a non-empty suffix is the only accepted shape.
- **Concurrent access — module state**: `integrationsApi` holds no shared mutable state between calls (per
  `stateless-module`), so there is nothing for two concurrent calls to race on within this module itself.
- **Concurrent access — repeat `connect` calls**: both calls are sent; see **connect-repeat-call-ordering**
  below.
- **Concurrent access — repeat `rotateWebhookSecret` calls**: calling `rotateWebhookSecret` twice in
  succession MUST NOT be treated as idempotent — each call mints a distinct new secret and invalidates
  whatever secret the config held immediately before, by design (`rotate-webhook-secret-is-destructive`);
  this is the opposite of `adoptInstallations`'s documented safe-to-repeat behavior.
- **Error states — malformed test request vs. refused credential**: a malformed `testProviderConfig`/
  `testProviderCredentials` request (unknown provider, undeclared field, non-testable provider) MUST throw,
  while a syntactically valid request the provider simply refuses MUST resolve with `ok: false`
  (`test-result-ok-false-is-not-an-error`) — these are two distinct failure shapes a caller must not
  conflate.
- **Error states — sync with no worker**: `sync-no-worker-throws-503` is the one documented, provider-scoped
  status code this client's own comments call out by number; every other non-2xx status is handled only
  generically, via `AuthHttpError`'s `status`/`code`.
- **Offline or disconnected state**: no `integrationsApi` method catches a network-level `fetch` rejection or
  retries beyond the single inherited `401` refresh-and-retry waterfall (`session-refresh-waterfall`); a
  connectivity loss mid-call propagates as an unhandled promise rejection out of `integrationsApi` to the
  caller, with no queuing or offline-specific handling anywhere in this file.
- **No timeout**: no method in this file sets a deadline or passes an `AbortSignal`; a reachable-but-
  unresponsive backend leaves the call pending until the underlying `fetch` implementation's own limit, if
  any.
- **No cancellation**: no method accepts an `AbortSignal` parameter, so a caller cannot cancel an in-flight
  request through this module.
- **`oauthCallbackUrl` outside a browser**: calling it where `window` is undefined (e.g. during
  server-side rendering) MUST throw whatever `ReferenceError` accessing `window.location` produces in that
  environment — a documented, client-only precondition (`oauth-callback-url-is-origin-relative`), not a
  gap this client guards against.
- **connect-repeat-call-ordering**: each `connect` call issues exactly one `POST /integrations/connect` with no idempotency key and no client-side de-duplication; two calls for the same `providerId`/`serviceType`/`ecosystemId`/external account — concurrent, or one retried after a dropped response — both reach the backend, which alone decides whether the second is an upsert, a conflict, or a second connection. Unlike `adoptInstallations`, no comment documents a repeat `connect` as safe.

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

## Localization

Not applicable: `integrations.ts` and `wire.ts` author no user-facing string literal of their own — every
runtime string this module builds is a URL, a JSON key, or a fixed structural constant (`BASE`,
`OAUTH_CALLBACK_PATH`); every message a caller can observe (`AuthHttpError.message`, `IntegrationTestResult.summary`,
`AdoptedInstallationRow.skipped`/`.warning`) originates in the backend's response body, extracted by
`extractErrorMessage`/`extractErrorCode` in `auth/src/client.ts`, not authored here.

## Accessibility Options

Not applicable: `integrations.ts`/`wire.ts` render no UI and respond to none of Reduce Motion, Increase
Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: no given source in this component gates its own behavior behind a feature-flag check of any
kind.

## Analytics

Not applicable: no given source calls an analytics or event-emission API of any kind.

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

## Logging

Not applicable: `integrations.ts` and `wire.ts` contain no logging call of any kind.

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

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/integrations/` |

## Design Decisions

**Decision**: `configPath` (used with a `providerId`) and `configByIdPath` (used with a `configId`) are two
separate private helper functions in `integrations.ts` that produce the identical URL template.
**Rationale**: the file keeps them separate because they express two different addressing *schemes* over the
same underlying route shape — a provider slug for the legacy provider-id-addressed CRUD group, and a
uuid/rdid for the newer id/rdid-addressed CRUD group — even though nothing in the URL itself distinguishes
which scheme a given call is using; the backend must tell a provider slug apart from a config id/rdid by the
value's own shape, not by the route. This recipe records the duplication as an observed structural fact of
the source rather than "fixing" it to one helper, since collapsing them would change which named function a
port's own two addressing schemes call through.
**Approved**: pending

**Decision**: `getAuthUrl`/`getInstallUrl` build their query strings with `URLSearchParams`, while
`listConnections`'s `ecosystemId` query parameter is encoded manually via string interpolation with `enc`.
**Rationale**: both mechanisms percent-encode their values correctly, so there is no functional divergence,
but the file uses two different idioms for the same kind of task; this is recorded as an observed stylistic
inconsistency, not corrected to one convention, since a port is free to standardize on either without
changing observable behavior.
**Approved**: pending

**Decision**: `decodeOAuthStateClaims` deliberately ignores the signature half of the `state` value it
decodes, and `isOAuthStateFresh`'s window is deliberately wider than the backend's own by
`OAUTH_STATE_CLOCK_GRACE_MS` in both directions.
**Rationale**: the source's own comments are explicit on both points: nothing here is a security decision,
because every recovered claim is re-verified by the backend before `connect` persists anything, so a forged
`state` is no more dangerous decoded than undecoded; and the pre-flight window is widened, rather than
mirrored exactly, so that the two independent clocks involved (the operator's browser and the backend) never
cause this client to refuse a `state` the backend would have accepted — the reverse (this client accepting
one the backend then rejects) only ever costs the `POST` that would have happened anyway, answered by the
backend's own verdict.
**Approved**: pending

**Decision**: `AdoptedInstallationRow.warning` is declared and documented in `wire.ts`, but no given source
in `integrations.ts` reads or surfaces it.
**Rationale**: `wire.ts`'s own comment on the field states this is deliberate rather than an oversight — the
sentence an operator sees about a failed cache warm is authored by the backend's own test narrator, which
reads this field server-side; a prior client-side copy of that narration was removed once the field existed
to carry it from the server instead. This recipe documents the field as part of the wire contract (a port
must still decode it, since the response really carries it) without inventing a consumer for it that these
given sources do not have.
**Approved**: pending

**Decision**: `rotate-webhook-secret-requires-caller-confirmation` is written as a SHOULD, not a MUST.
**Rationale**: `integrations.ts` is a stateless request-builder with no UI of its own — it cannot itself
enforce a confirmation step, since confirming is a presentation-layer concern outside these two files' given
sources (the source's own comment says only that "callers must confirm before firing it"). Writing it as
MUST would describe a guarantee this module cannot make; SHOULD records the expectation for whatever
presentation layer wires a button to `rotateWebhookSecret`, without overstating what this file itself
enforces.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | Security |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |

`separation-of-concerns` passes: `integrations.ts`/`wire.ts` contain zero UI or presentation code — both
files are a plain request-builder layer consumed by a separate presentation layer, per the module's own
top-of-file comment. `unit-test-coverage` is `failed`: none of `integrationsApi`'s twenty methods, nor
`decodeOAuthStateClaims`/`isOAuthStateFresh`, has a test file adjacent to `integrations.ts`/`wire.ts`
anywhere in this checkout — the closest exercise of `decodeOAuthStateClaims`/`isOAuthStateFresh` is an
indirect one, through a consumer component's own test (`IntegrationsOAuthCallback.test.tsx`), which is
outside this component's given sources. `explicit-error-handling` passes: every failure either throws
`AuthHttpError` (via the shared `authedFetch`) or is the explicit `isNotFound`-gated `null` return in
`getProviderConfig`/`getProviderConfigById`; nothing in this file catches and discards an error.
`input-sanitization` is `partial`: `decodeOAuthStateClaims`'s grammar and field-type checks
(`decode-state-claims-grammar`, `decode-state-claims-field-validation`) are real input validation, and
`isOAuthStateFresh` adds a documented freshness check on top — but neither is authoritative
(`decode-state-claims-never-verifies-signature`), and every write method (`putProviderConfig`,
`createProviderConfig`, `connect`, and the rest) forwards its caller-supplied body with no client-side shape
or charset validation of its own, deferring entirely to the backend. `secure-storage` is `partial`: the OAuth
client secret and GitHub App private key are never returned in plaintext by this client (`secrets-are-write-only`),
and `integrationsApi` itself persists nothing (`no-client-side-cache`) — but the deliverability
webhook secret is passed through unredacted on every read that carries it
(**webhook-secret-visibility-after-mint**).
`idempotent-operations` is `partial`: `adoptInstallations` is explicitly documented safe to call more than
once (`adopt-installations-idempotent`), but `rotateWebhookSecret` is explicitly *not* idempotent by design
(each call mints a new secret), and `connect` sends every repeat call with no idempotency key
(**connect-repeat-call-ordering**). `error-response-handling` is `partial`: every call exposes a status and
optional code for the caller to branch on, and two specific codes are documented by name in this client's own
comments (`404` → `null` for the two get-by-id lookups, `503` → "no worker" for `sync`), but every other
method offers no per-code handling beyond the generic `AuthHttpError` propagation.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
