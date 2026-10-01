---
id: 45c318d7-dd3e-491c-8811-eb2a3d79bca9
title: Integrations
domain: agentictoolkit://cookbook/adh/hub/integrations
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Client for /api/integrations: the provider catalog, ecosystem provider
  configs and connections, OAuth/install/link-token endpoints, and OAuth state claims.'
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
- agentictoolkit://cookbook/adh/hub/access
- agentictoolkit://cookbook/adh/hub/ecosystems/ecosystem-config
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

# Integrations

## Overview

This is the client for the `/api/integrations` surface. It covers three things: the
provider catalog (every provider the platform can integrate, with its auth method and
capabilities); an ecosystem's own, owner-scoped provider configs (OAuth client
credentials or a GitHub App's identity, plus optional endpoint overrides, addressed two
different ways — by a provider id and by the config's own id/rdid); and an ecosystem's
connections (linked accounts) — list, connect (all six connect-request auth methods),
disconnect, sync-now, per-connection sync settings, plus the OAuth/app-install/
self-hosted-instance/Plaid-Link start endpoints and a local, non-authoritative decoder
for the signed OAuth `state` round-trip value. The client exposes twenty
request-building operations plus four standalone OAuth-callback-path and state-claim
helpers, all built on a shared authenticated-request helper and a percent-encoding
helper for path segments. It is a headless **logic** module — no visual surface — so
this recipe marks Appearance, States, and Accessibility not applicable and carries the
runtime contract entirely in Behavioral Requirements, per the non-UI component guidance
this recipe was authored under.

## Behavioral Requirements

**Provider catalog**

- **provider-catalog-fetch**: Listing providers MUST send `GET {BASE}/providers`, where `BASE` is
  the fixed constant `/api/integrations`, and MUST return the providers array unwrapped from the
  `{ providers }` response envelope.

**Provider configs — provider-id-addressed**

- **provider-config-list**: Listing provider configs MUST send `GET {BASE}/ecosystems/<enc(ecosystemId)>/provider-configs`
  and MUST return the configs array unwrapped from `{ configs }`.
- **provider-config-get-by-provider-id**: Getting a provider config by provider id MUST send `GET {BASE}/ecosystems/<enc(ecosystemId)>/provider-configs/<enc(providerId)>`.
- **provider-config-get-not-found-null**: Getting a provider config by provider id MUST return `null`, not throw, when that
  request fails with a not-found response (a backend `404`); any other thrown error MUST propagate unchanged.
- **provider-config-put-preserves-blank-secret**: Saving a provider config by provider id MUST send `PUT` to that same
  path with the given provider-config input JSON-serialized verbatim as the body; per that input's own `clientSecret`
  field's documented contract, a blank or absent `clientSecret` in that body MUST preserve the config's currently stored
  secret rather than clearing it.
- **provider-config-delete-by-provider-id**: Deleting a provider config by provider id MUST send `DELETE` to that same
  path and MUST resolve with no value.

**Provider configs — id/rdid-addressed**

- **provider-config-create**: Creating a provider config MUST send `POST {BASE}/ecosystems/<enc(ecosystemId)>/provider-configs`
  (the collection path, with no trailing id segment) with a body naming the provider id, a name, and the same input
  fields as saving-by-provider-id, JSON-serialized verbatim, and MUST return the resulting provider config record.
- **provider-config-get-by-id**: Getting a provider config by id MUST send `GET {BASE}/ecosystems/<enc(ecosystemId)>/provider-configs/<enc(configId)>`.
- **provider-config-get-by-id-not-found-null**: Getting a provider config by id MUST return `null`, not throw, on a
  not-found response, matching provider-config-get-not-found-null's pattern for the provider-id-addressed lookup.
- **provider-config-update-by-id**: Updating a provider config by id MUST send `PUT` to that same id-addressed path with
  a provider-config input body optionally extended with a `name`.
- **provider-config-delete-by-id**: Deleting a provider config by id MUST send `DELETE` to that same id-addressed path
  and MUST resolve with no value.
- **provider-config-two-address-schemes-share-a-url-shape**: the provider-id-addressed path (built by a private
  path-building helper given a provider id) and the id/rdid-addressed path (built by a second private path-building
  helper) MUST both resolve to the identical template `{BASE}/ecosystems/<enc(ecosystemId)>/provider-configs/<enc(...)>`
  — the two helpers differ only in the name of the parameter they encode into the trailing segment, never in the URL
  shape produced (see Design Decisions).

**Credential testing**

- **test-saved-config**: Testing a saved provider config MUST send `POST` to the id-addressed config path's `/test`
  sub-path and MUST return a test-result record.
- **test-saved-config-github-app-also-connects**: for a `github_app` provider, testing a saved provider config IS the
  connect: the only proof an app id and private key are real is minting a JWT and enumerating the installations the
  app can see, and that enumeration itself creates the connection rows and warms the repository cache. The test
  result's `adopted` field, when present, MUST report the outcome of that side effect (connected/skipped
  installations), and a caller holding a connection list MUST refresh it whenever `adopted` is present.
- **test-result-ok-false-is-not-an-error**: a refused credential MUST resolve either testing operation with `{ ok:
  false, summary, notes }`, never throw; only a malformed request (an unknown provider, a field the provider does not
  declare, or a provider with no way to be tested at all) MUST throw.
- **test-draft-credentials-writes-nothing**: Testing draft credentials MUST send `POST {BASE}/providers/<enc(providerId)>/test-credentials`
  with the given credentials body, and MUST NOT create or modify a provider config, a connection, or a repository
  cache — the whole difference from testing a saved config.
- **test-draft-credentials-with-stored-secret**: when the credentials body's `providerConfigId` is given with a blank
  `clientSecret`, testing draft credentials MUST test against that config's already-stored secret rather than an empty
  one, because a saved secret is never re-displayed in an edit form (it is write-only): a blank field there means
  "unchanged," not "no secret."

**Transfer**

- **transfer-request-shape**: Transferring a provider config MUST send `POST` to the id-addressed config path's
  `/transfer` sub-path with a body naming a `targetEcosystemId` and MUST return a transfer-result record.
- **transfer-moves-credential-connections-and-caches-together**: the result MUST report the moved config's credential,
  the connections it minted, and their cached repository lists as having moved together in one result; the caller
  MUST manage both the source and destination ecosystem after a transfer.
- **transfer-mints-new-rdid**: the transferred config's `rdid` MUST be treated as re-minted at the destination
  ecosystem; the address it answered to before the transfer MUST NOT be assumed to still resolve.
- **transfer-connections-count-is-live-only**: the transfer result's connection count MUST count only connections that
  are live at the destination, not the number of connection rows that were moved; a moved connection that was already
  disconnected MUST NOT be counted.

**Webhook secret rotation**

- **rotate-webhook-secret-request-shape**: Rotating a webhook secret MUST send `POST` to the id-addressed config
  path's `/rotate-webhook-secret` sub-path with no body and MUST return the updated provider config record.
- **rotate-webhook-secret-is-destructive**: the newly minted secret MUST invalidate the previously stored one
  immediately; per the source's own comment, a provider still configured with the old secret is expected to start
  failing its own delivery attempts at the provider's side with no signal raised by this client.
- **rotate-webhook-secret-also-generates-first-secret**: for a provider config record whose deliverability-webhook
  secret is `null` (a config created before per-config secrets existed), rotating the webhook secret MUST be the only
  operation in this client that gives that config a working secret.

**Connections**

- **connections-list-scoped-by-ecosystem**: Listing connections MUST send `GET {BASE}?ecosystemId=<enc(ecosystemId)>`
  and MUST return the connections array unwrapped from `{ connections }`, across every provider owned by that
  ecosystem.
- **connect-request-shape**: Connecting MUST send `POST {BASE}/connect` with the given connect-request body
  JSON-serialized verbatim and MUST return the resulting connection record.
- **connect-every-variant-names-ecosystem**: every member of the connect-request body's six auth-method variants
  (`oauth`, `api_key`, `app_password`, `plaid_link`, `oauth_instance`, `github_app`, keyed by `type`) MUST include
  `ecosystemId`; connecting names the target ecosystem in the body on every call regardless of auth method.
- **connect-github-app-has-no-code**: the `github_app` variant MUST carry `installationId` and MUST NOT carry a
  `code` field — unlike every other variant, which exchanges an authorization code, a GitHub App installation is not
  an authorization to exchange; it already exists and is addressed by id.
- **connect-app-password-source-exclusivity-delegated**: the `app_password` variant MAY supply inline credentials
  (`identifier`, `password`, `instanceUrl`) or a `providerConfigId` to source them from a saved ecosystem provider
  config; connecting MUST NOT reject a body that supplies both or neither — per the variant's own documented
  contract, that exclusivity is enforced server-side, not by this client.
- **disconnect-request-shape**: Disconnecting MUST send `DELETE {BASE}/<enc(connectionId)>` and MUST resolve with no
  value; it soft-deletes a connection the caller owns.
- **sync-request-shape**: Syncing a connection MUST send `POST {BASE}/<enc(connectionId)>/sync` and MUST resolve with
  no value on success.
- **sync-no-worker-throws-503**: Syncing a connection MUST throw an error carrying status `503` when no worker is
  registered yet for the connection's provider; per the source's own comment, the caller shows this as an inline "not
  available" note rather than a hard error.
- **patch-settings-request-shape**: Patching a connection's sync settings MUST send `PATCH {BASE}/<enc(connectionId)>/settings`
  with the given settings body and MUST return the result (`{ ok, syncSettings }`) verbatim.

**OAuth / install / instance / link-token start endpoints**

- **auth-url-request-shape**: Getting an OAuth authorization URL MUST send `GET {BASE}/providers/<enc(providerId)>/auth-url`
  with query parameters `ecosystemId` and `redirectUri` always present, and `serviceType`/`scopes` appended only when
  given, and MUST return a result (`{ url, state }`).
- **install-url-request-shape**: Getting an app-install URL MUST send `GET {BASE}/providers/<enc(providerId)>/install-url`
  with query parameter `ecosystemId` always present and `serviceType` appended only when given; it MUST NOT send a
  `redirectUri` or `scopes` parameter — a GitHub App's setup URL is configured on the app at the provider, not
  supplied per request, and its permissions are declared on the app rather than negotiated per call.
- **adopt-installations-request-shape**: Adopting installations MUST send `POST {BASE}/providers/<enc(providerId)>/adopt-installations`
  with the given body and MUST return a result (`{ connected, skipped }`).
- **adopt-installations-requires-config-id**: the adopt-installations body's `providerConfigId` MUST be a required
  field; per the source's own comment, the app's identity MUST be read by that id rather than resolved any other way,
  because a resolver that falls through to a platform-global app would surface installations belonging to other
  tenants.
- **adopt-installations-idempotent**: calling adopt-installations a second time for the same saved config MUST report
  an already-connected installation under `skipped` rather than creating a duplicate connection; the operation MUST
  be safe to call more than once.
- **register-instance-request-shape**: Registering a self-hosted instance MUST send `POST {BASE}/providers/<enc(providerId)>/register-instance`
  with the given body and MUST return a result (`{ state, authorizeUrl, clientId }`).
- **register-instance-config-id-overrides-instance-url**: when the register-instance body's `providerConfigId` is
  set, the per-instance `clientId`/`clientSecret`/`instanceUrl` MUST be sourced from that saved provider config
  instead of a dynamic per-user app registration, even though the body's `instanceUrl` remains a required field and
  is sent — but ignored on this path.
- **create-link-token-request-shape**: Creating a link token MUST send `POST {BASE}/providers/<enc(providerId)>/link-token`
  with the given body, or `{}` when no body is given, and MUST return `{ linkToken }`.

**OAuth callback path and state claims**

- **oauth-callback-path-fixed**: the OAuth callback path MUST be the fixed string `/integrations/oauth-callback`,
  shared by the connect flow that builds a `redirectUri` from it and the callback page that receives the provider's
  redirect, so both agree on the path.
- **oauth-callback-url-is-origin-relative**: building the OAuth callback URL MUST return `<origin><OAuth callback
  path>`; it MUST be called only in a browser context, since it reads the current page's origin with no guard (a
  documented, client-only precondition).
- **decode-state-claims-grammar**: decoding OAuth state claims MUST return `null` for any `state` string that has no
  `.` separator, or whose `.` is the first character, or whose `.` is the last character.
- **decode-state-claims-base64url-json**: decoding OAuth state claims MUST decode only the substring before the `.`
  as base64url-encoded, fatal-UTF-8-decoded JSON, and MUST return `null` when that decode fails or produces a
  non-object value.
- **decode-state-claims-field-validation**: decoding OAuth state claims MUST return `null` unless the decoded
  object's `customerId`, `providerId`, `serviceType`, and `ecosystemId` are all non-empty strings and its `iat` is a
  finite number; when all five checks pass it MUST return claims carrying exactly those five fields.
- **decode-state-claims-never-verifies-signature**: decoding OAuth state claims MUST NOT verify the signature half of
  `state` — per the source's own comment, it exists only to let this client answer questions like the state-freshness
  check locally; every value it recovers MUST still be re-verified by the backend (signature, caller identity,
  ecosystem) before the connect request persists anything, and a forged `state` MUST get the same rejection it would
  have gotten without this function.
- **state-freshness-window**: checking OAuth state freshness MUST return `true` only when `now - claims.iat` is
  between `-(OAUTH_STATE_FUTURE_SKEW_MS + OAUTH_STATE_CLOCK_GRACE_MS)` and `OAUTH_STATE_TTL_MS + OAUTH_STATE_CLOCK_GRACE_MS`
  inclusive, using the current time when the caller does not supply one.
- **state-freshness-constants**: `OAUTH_STATE_TTL_MS` MUST be `600000` (10 minutes), `OAUTH_STATE_FUTURE_SKEW_MS`
  MUST be `60000` (1 minute), and `OAUTH_STATE_CLOCK_GRACE_MS` MUST be `30000` (30 seconds).

**Cross-cutting**

- **every-identifier-url-encoded**: every path-segment identifier this client builds (`ecosystemId`, `providerId`,
  `configId`, `connectionId`) MUST be percent-encoded before being placed in a URL path.
- **no-client-side-cache**: the client MUST NOT cache or memoize any response; every operation issues exactly one
  HTTP request per call.
- **stateless-module**: the client and its standalone exported functions MUST hold no mutable module-level state
  across calls; the only module-level values are the base-path string constant and the three OAuth-state numeric
  constants, all fixed.
- **errors-propagate-except-not-found-lookups**: every client operation MUST let a non-2xx response propagate as a
  thrown error, except getting a provider config by provider id and by id, which MUST catch a `404` specifically and
  resolve `null` instead.

### Security

This is a security-relevant recipe: it manages OAuth authorization flows, ecosystem-scoped provider
credentials (masked OAuth client secrets and GitHub App private keys), and per-config inbound webhook
secrets.

- **secrets-are-write-only**: a provider config's `clientSecret` MUST never be echoed back by any read
  operation in this client — listing provider configs and getting one by provider id or by id all
  return a masked config row whose `hasSecret: boolean` reports only whether a secret is stored, never
  its value.
- **webhook-secret-visibility-after-mint**: the deliverability-webhook secret is typed `string | null`
  (`null` means "no secret is stored yet") and is passed through exactly as the backend returns it on
  every read — listing, getting by provider id, getting by id, and rotating the webhook secret alike.
  Unlike `clientSecret`, which every wire row redacts to `hasSecret: boolean`, this client applies no
  redaction to the webhook secret; whether a later read carries it in cleartext is decided by the
  backend, not by this module.
- **oauth-state-claims-not-authorization**: the OAuth `state` this client decodes carries `customerId`,
  `providerId`, `serviceType`, and `ecosystemId` in cleartext (base64url-encoded, not encrypted) with
  only an HMAC signature for integrity; decoding OAuth state claims' output MUST NOT be used for any
  authorization decision by a caller of this module — per decode-state-claims-never-verifies-signature,
  it informs a pre-flight check only, never a write.
- **ecosystem-scoping-authorized-server-side**: every operation in this client that names an
  `ecosystemId` MUST rely on the backend to authorize the caller against it; this client performs no
  client-side ecosystem-membership check, and per the module's own top-of-file comment a caller
  addressing an ecosystem it does not own MUST receive a thrown error with status `403`, never a silent
  success or crash.
- **rotate-webhook-secret-requires-caller-confirmation**: rotating a webhook secret SHOULD NOT be
  triggered without positive caller confirmation, because the immediate invalidation of the previous
  secret (rotate-webhook-secret-is-destructive) cannot be undone through this client (see Design
  Decisions for why this is a SHOULD, not a MUST, at this layer).
- **session-refresh-waterfall**: a `401` response to any client call MUST trigger exactly one token
  refresh and one retried request, inherited unconditionally from the shared authenticated-request
  mechanism; a second `401` on the retried request MUST propagate as a thrown error with `status: 401`.
  This module defines no refresh or retry logic of its own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause the
  call to throw an error, carrying the response's HTTP status and, when the body supplies one, a
  machine-readable `code`.

## Appearance

Not applicable — this is the integrations data-access client, not a visual component.

## States

Not applicable — this is the integrations data-access client, not a visual component; any loading, error,
or empty visual state is owned by the presentation layer that consumes this client. The only runtime
state machine this component defines is the OAuth `state` freshness window, specified under Behavioral
Requirements (`state-freshness-window`), not here.

## Accessibility

Not applicable — this is the integrations data-access client, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-integrations-001 | provider-catalog-fetch | list providers, against a response `{ providers: [{ providerId: "github", authMethod: "github_app", testable: true, ... }] }` | Request URL is `/api/integrations/providers`; resolves to that array unwrapped from the envelope |
| hub-domain-integrations-002 | provider-config-list | list provider configs for ecosystem id "eco-1" | `GET /api/integrations/ecosystems/eco-1/provider-configs`; resolves to the configs array unwrapped |
| hub-domain-integrations-003 | provider-config-get-by-provider-id, provider-config-get-not-found-null | get provider config for ecosystem id "eco-1", provider id "github", against a `404` response | Resolves to `null`, does not throw |
| hub-domain-integrations-004 | provider-config-put-preserves-blank-secret | save provider config for ecosystem id "eco-1", provider id "github", with body `{ clientId: "x" }` (no `clientSecret`) | `PUT /api/integrations/ecosystems/eco-1/provider-configs/github` with body `{ clientId: "x" }` only; the stored secret is unchanged per the field's own contract |
| hub-domain-integrations-005 | provider-config-delete-by-provider-id | delete provider config for ecosystem id "eco-1", provider id "github" | `DELETE /api/integrations/ecosystems/eco-1/provider-configs/github`; resolves to `undefined` |
| hub-domain-integrations-006 | provider-config-create | create provider config for ecosystem id "eco-1" with body `{ providerId: "github", name: "Prod" }` | `POST /api/integrations/ecosystems/eco-1/provider-configs` (no trailing id) with that body; resolves to a provider config record |
| hub-domain-integrations-007 | provider-config-get-by-id, provider-config-two-address-schemes-share-a-url-shape | get provider config for ecosystem id "eco-1" by id "cfg-uuid-1" | `GET /api/integrations/ecosystems/eco-1/provider-configs/cfg-uuid-1` — an identical URL template to the provider-id lookup's, differing only in what the trailing segment addresses |
| hub-domain-integrations-008 | provider-config-get-by-id-not-found-null | get provider config for ecosystem id "eco-1" by id "cfg-missing", against a `404` response | Resolves to `null`, does not throw |
| hub-domain-integrations-009 | provider-config-update-by-id | update provider config "cfg-1" in ecosystem "eco-1" with body `{ name: "Renamed" }` | `PUT /api/integrations/ecosystems/eco-1/provider-configs/cfg-1` with body `{ name: "Renamed" }` |
| hub-domain-integrations-010 | provider-config-delete-by-id | delete provider config "cfg-1" in ecosystem "eco-1" | `DELETE /api/integrations/ecosystems/eco-1/provider-configs/cfg-1`; resolves to `undefined` |
| hub-domain-integrations-011 | test-saved-config, test-result-ok-false-is-not-an-error | test saved config "cfg-1" in ecosystem "eco-1", against a stub returning `{ ok: false, summary: "Invalid token", notes: [] }` | `POST /api/integrations/ecosystems/eco-1/provider-configs/cfg-1/test`; resolves (does not throw) to that body |
| hub-domain-integrations-012 | test-saved-config-github-app-also-connects | test a `github_app` saved config, stub returns `{ ok: true, adopted: { connected: [...], skipped: [] } }` | Resolves with `adopted` present; caller must refresh its connection list |
| hub-domain-integrations-013 | test-draft-credentials-writes-nothing, test-draft-credentials-with-stored-secret | test draft credentials for provider "github" with body `{ ecosystemId: "eco-1", providerConfigId: "cfg-1" }` (`clientSecret` omitted) | `POST /api/integrations/providers/github/test-credentials` with `providerConfigId` and no `clientSecret`; tests the stored secret; creates no config, connection, or cache |
| hub-domain-integrations-014 | transfer-request-shape, transfer-moves-credential-connections-and-caches-together, transfer-mints-new-rdid | transfer config "cfg-1" from ecosystem "eco-1" with body `{ targetEcosystemId: "eco-2" }` | `POST .../cfg-1/transfer`; the result's config has `ecosystemId === "eco-2"` with a new `rdid`; the result's connections and repository caches are both present in the same result |
| hub-domain-integrations-015 | transfer-connections-count-is-live-only | A transfer moving 3 connection rows, 1 already disconnected | the result's connection count is 2 |
| hub-domain-integrations-016 | rotate-webhook-secret-request-shape, rotate-webhook-secret-is-destructive | rotate webhook secret for config "cfg-1" in ecosystem "eco-1" | `POST .../cfg-1/rotate-webhook-secret` with no body; returns the updated config; the previously stored secret is no longer the one returned |
| hub-domain-integrations-017 | rotate-webhook-secret-also-generates-first-secret | rotate webhook secret on a config whose deliverability-webhook secret is `null` | The returned config's deliverability-webhook secret is non-null |
| hub-domain-integrations-018 | connections-list-scoped-by-ecosystem | list connections for ecosystem "eco-1" | `GET /api/integrations?ecosystemId=eco-1`; resolves to the connections array unwrapped |
| hub-domain-integrations-019 | connect-request-shape, connect-every-variant-names-ecosystem | connect with body `{ type: "oauth", providerId: "github", serviceType: "repos", ecosystemId: "eco-1", code: "abc", redirectUri: "https://x/cb", state: "s.sig" }` | `POST /api/integrations/connect` with that body verbatim; resolves to a connection record |
| hub-domain-integrations-020 | connect-github-app-has-no-code | connect with body `{ type: "github_app", providerId: "github", serviceType: "repos", ecosystemId: "eco-1", installationId: "12345", state: "s.sig" }` | Request body has `installationId` and no `code` field |
| hub-domain-integrations-021 | connect-app-password-source-exclusivity-delegated | connect with body `{ type: "app_password", providerId: "mastodon", serviceType: "posts", ecosystemId: "eco-1", identifier: "me", password: "pw", providerConfigId: "cfg-1" }` (both inline credentials AND `providerConfigId` present) | The body is sent unchanged; connecting performs no client-side rejection of the combination |
| hub-domain-integrations-022 | disconnect-request-shape | disconnect connection "conn-1" | `DELETE /api/integrations/conn-1`; resolves to `undefined` |
| hub-domain-integrations-023 | sync-request-shape, sync-no-worker-throws-503 | sync connection "conn-1" against a `503` response | `POST /api/integrations/conn-1/sync`; throws an error with `status: 503` |
| hub-domain-integrations-024 | patch-settings-request-shape | patch settings for connection "conn-1" with body `{ gmailLabelIds: ["INBOX"] }` | `PATCH /api/integrations/conn-1/settings` with that body; resolves to `{ ok, syncSettings }` |
| hub-domain-integrations-025 | auth-url-request-shape | get auth URL for provider "github" with `{ ecosystemId: "eco-1", redirectUri: "https://x/cb" }` | `GET .../providers/github/auth-url?ecosystemId=eco-1&redirectUri=...` with no `serviceType`/`scopes` parameter present |
| hub-domain-integrations-026 | install-url-request-shape | get install URL for provider "github" with `{ ecosystemId: "eco-1" }` | `GET .../providers/github/install-url?ecosystemId=eco-1` with no `redirectUri` or `scopes` parameter anywhere in the URL |
| hub-domain-integrations-027 | adopt-installations-request-shape | adopt installations for provider "github" with `{ ecosystemId: "eco-1", providerConfigId: "cfg-1" }` | `POST .../providers/github/adopt-installations` with that body; resolves to `{ connected, skipped }` |
| hub-domain-integrations-028 | adopt-installations-requires-config-id | constructing an adopt-installations body without `providerConfigId` | Fails to typecheck against the required field; confirmed by the type declaration, no runtime test needed |
| hub-domain-integrations-029 | adopt-installations-idempotent | adopt installations called twice with the same `providerConfigId` against an installation already connected | The second call reports it under `skipped`, not `connected`; no duplicate connection is created |
| hub-domain-integrations-030 | register-instance-request-shape, register-instance-config-id-overrides-instance-url | register instance for provider "mastodon" with `{ ecosystemId: "eco-1", instanceUrl: "https://example.social", redirectUri: "https://x/cb", providerConfigId: "cfg-1" }` | `POST .../providers/mastodon/register-instance` with that body; the returned `clientId` is sourced from "cfg-1", even though `instanceUrl` is present in the sent body |
| hub-domain-integrations-031 | create-link-token-request-shape | create link token for provider "plaid" (no body) | `POST .../providers/plaid/link-token` with body `{}`; resolves to `{ linkToken }` |
| hub-domain-integrations-032 | oauth-callback-path-fixed, oauth-callback-url-is-origin-relative | build the OAuth callback URL with the page origin `"https://app.example.test"` | Returns `"https://app.example.test/integrations/oauth-callback"` |
| hub-domain-integrations-033 | decode-state-claims-grammar | decode OAuth state claims from `"nodothere"` | Returns `null` (no `.` present) |
| hub-domain-integrations-034 | decode-state-claims-grammar | decode OAuth state claims from `".abc"` | Returns `null` (the `.` is the first character) |
| hub-domain-integrations-035 | decode-state-claims-grammar | decode OAuth state claims from `"abc."` | Returns `null` (the `.` is the last character) |
| hub-domain-integrations-036 | decode-state-claims-base64url-json, decode-state-claims-field-validation | decode OAuth state claims from a value whose prefix base64url-decodes to `{"customerId":"c1","providerId":"github","serviceType":"repos","ecosystemId":"eco-1","iat":1000}`, followed by `.` and any suffix | Returns `{ customerId: "c1", providerId: "github", serviceType: "repos", ecosystemId: "eco-1", iat: 1000 }` |
| hub-domain-integrations-037 | decode-state-claims-field-validation | Same claims object but with `ecosystemId: ""` | Returns `null` |
| hub-domain-integrations-038 | decode-state-claims-never-verifies-signature | The same well-formed claims prefix from vector 036, but with an arbitrary, invalid signature suffix | Still returns the decoded claims — the signature is never checked |
| hub-domain-integrations-039 | state-freshness-window, state-freshness-constants | check OAuth state freshness for `{ iat: 0 }` at time `630000` | Returns `true` (exactly at the widened upper bound: `600000 + 30000`) |
| hub-domain-integrations-040 | state-freshness-window | check OAuth state freshness for `{ iat: 0 }` at time `630001` | Returns `false` (one millisecond past the widened upper bound) |
| hub-domain-integrations-041 | state-freshness-window | check OAuth state freshness for `{ iat: 100000 }` at time `9999` | Returns `true` (`now - iat = -90001`... boundary case: exactly `-90000` is the widened lower bound, one past it is `false`) |
| hub-domain-integrations-042 | every-identifier-url-encoded | disconnect connection id `"a/b"` | `DELETE /api/integrations/a%2Fb` |
| hub-domain-integrations-043 | no-client-side-cache, stateless-module | list providers, called twice in a row | Two separate HTTP requests are issued; the second call is not served from any in-module cache |
| hub-domain-integrations-044 | errors-propagate-except-not-found-lookups | get provider config for ecosystem "eco-1", provider "github", against a `500` response | The `500` propagates as a thrown error; it is not converted to `null` (unlike a `404`) |
| hub-domain-integrations-045 | secrets-are-write-only | list provider configs for ecosystem "eco-1", response body | No element of the resolved array has a `clientSecret` field; each has only `hasSecret: boolean` |
| hub-domain-integrations-046 | ecosystem-scoping-authorized-server-side | list connections for ecosystem "eco-2", called by a caller who does not own "eco-2" | The call rejects with an error, `status: 403` |
| hub-domain-integrations-047 | session-refresh-waterfall | Any client call's first response is `401`; a token refresh resolves a new token | The request is retried once with the new token; a `401` on that retry throws an error with `status: 401` — traced to the shared authenticated-fetch mechanism, exercised only indirectly through this client |

## Edge Cases

- **Null and empty input — path identifiers**: ecosystem id / provider id / config id / connection id
  are typed `string` and are not checked for emptiness client-side; an empty value is still
  percent-encoded (to the empty string) and sent, producing a request the backend answers with its own
  `404`/`400` — a non-empty identifier is a caller precondition, per the module's own top-of-file
  comment naming the ecosystem id as something "the caller must manage."
- **Null and empty input — `state`**: decoding OAuth state claims MUST return `null` for the empty
  string (no `.` present, per decode-state-claims-grammar) rather than throw.
- **Null and empty input — creating a link token's optional body**: an omitted body argument MUST be
  sent as `{}`, per create-link-token-request-shape; there is no distinct "send nothing" path.
- **Boundary values — OAuth state freshness**: the widened window's both edges are inclusive per
  state-freshness-window; one millisecond outside either edge MUST flip the result, as vectors 039–041
  show.
- **Boundary values — `state` grammar**: a `.` at position `0` or at the last character position are
  both rejected by decode-state-claims-grammar; a `.` anywhere strictly between the first and last
  character of a non-empty prefix and a non-empty suffix is the only accepted shape.
- **Concurrent access — module state**: the client holds no shared mutable state between calls (per
  stateless-module), so there is nothing for two concurrent calls to race on within this module itself.
- **Concurrent access — repeat connect calls**: both calls are sent; see connect-repeat-call-ordering
  below.
- **Concurrent access — repeat rotate-webhook-secret calls**: calling rotate-webhook-secret twice in
  succession MUST NOT be treated as idempotent — each call mints a distinct new secret and invalidates
  whatever secret the config held immediately before, by design
  (rotate-webhook-secret-is-destructive); this is the opposite of adopt-installations's documented
  safe-to-repeat behavior.
- **Error states — malformed test request vs. refused credential**: a malformed test request (unknown
  provider, undeclared field, non-testable provider) MUST throw, while a syntactically valid request
  the provider simply refuses MUST resolve with `ok: false` (test-result-ok-false-is-not-an-error) —
  these are two distinct failure shapes a caller must not conflate.
- **Error states — sync with no worker**: sync-no-worker-throws-503 is the one documented,
  provider-scoped status code this client's own comments call out by number; every other non-2xx
  status is handled only generically, via the thrown error's status/code.
- **Offline or disconnected state**: no operation in this client catches a network-level request
  rejection or retries beyond the single inherited `401` refresh-and-retry waterfall
  (session-refresh-waterfall); a connectivity loss mid-call propagates as an unhandled promise
  rejection out of this client to the caller, with no queuing or offline-specific handling anywhere in
  this file.
- **No timeout**: no operation in this file sets a deadline or passes a cancellation signal; a
  reachable-but-unresponsive backend leaves the call pending until the underlying request
  implementation's own limit, if any.
- **No cancellation**: no operation accepts a cancellation-signal parameter, so a caller cannot cancel
  an in-flight request through this module.
- **Building the OAuth callback URL outside a browser**: calling it where there is no browser page
  context (e.g. during server-side rendering) MUST throw whatever error accessing the page's location
  produces in that environment — a documented, client-only precondition
  (oauth-callback-url-is-origin-relative), not a gap this client guards against.
- **connect-repeat-call-ordering**: each connect call issues exactly one `POST /integrations/connect`
  with no idempotency key and no client-side de-duplication; two calls for the same provider id /
  service type / ecosystem id / external account — concurrent, or one retried after a dropped response
  — both reach the backend, which alone decides whether the second is an upsert, a conflict, or a
  second connection. Unlike adopt-installations, no comment documents a repeat connect as safe.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `BASE` | fixed constant, `"/api/integrations"` | fixed | Not injectable; every request path is built from it. |
| `OAUTH_CALLBACK_PATH` | fixed constant, `"/integrations/oauth-callback"` | fixed | The client route the OAuth/app-install redirect lands on; shared by the callback-URL builder and the callback page. |
| `OAUTH_STATE_TTL_MS` | fixed constant | `600000` (10 min) | How long a minted `state` is treated as fresh by this client's pre-flight check; mirrors (loosely) the backend's own TTL. |
| `OAUTH_STATE_FUTURE_SKEW_MS` | fixed constant | `60000` (1 min) | How far ahead of this client's clock an issuer's `iat` may be before this pre-flight treats the state as not-yet-valid. |
| `OAUTH_STATE_CLOCK_GRACE_MS` | fixed constant | `30000` (30 s) | Added to both bounds of the freshness window so this client's check can only be more permissive than the backend's own, never stricter. |
| `ecosystemId` (caller parameter) | string | none — required on nearly every call | The ecosystem every provider-config, connection, and OAuth-start call is scoped to; percent-encoded in every path/query use. |
| `providerId` (caller parameter) | string | none — required on provider-scoped calls | A catalog provider's id; percent-encoded. |
| `configId` / `connectionId` (caller parameter) | string | none — required on id-addressed calls | A provider config's or connection's own id/rdid; percent-encoded. |
| `body` (varies by operation) | a JSON object matching that operation's documented fields (the provider-config input, the connect-request's six type-keyed variants, the transfer/register/link-token/sync-settings/adopt-installations bodies) | none — required except creating a link token's, which defaults to `{}` | JSON-serialized verbatim as each write's body; see the matching Behavioral Requirement for the exact shape sent. |

## Deep Linking

| Platform | URL Pattern |
|----------|-------------|
| Web | `/integrations/oauth-callback` — the fixed landing route for a provider's OAuth/app-install redirect; the callback-URL builder returns the full redirect URI as `<page origin><callback path>`. |

This component's source only defines a web route; no Apple or Android route is defined here. A future
Apple or Android port would need its own equivalent redirect-landing registration (a custom URL scheme
or an associated-domains universal link on Apple, an App Link/deep link intent filter on Android) —
none of which exists in this checkout to describe.

## Localization

Not applicable: this client authors no user-facing string literal of its own — every runtime string
this module builds is a URL, a JSON key, or a fixed structural constant (the base path, the callback
path); every message a caller can observe (an error's message, a test result's summary, an
adopted-installation row's skipped/warning) originates in the backend's response body, extracted by the
shared error-message/error-code helpers, not authored here.

## Accessibility Options

Not applicable: this component renders no UI and responds to none of Reduce Motion, Increase Contrast,
or Differentiate Without Color.

## Feature Flags

Not applicable: no given source in this component gates its own behavior behind a feature-flag check of any
kind.

## Analytics

Not applicable: no given source calls an analytics or event-emission API of any kind.

## Privacy

- **Data collected**: this module originates no analytics of its own. It transports the provider
  catalog (no end-user data), ecosystem provider configs (OAuth client credentials or a GitHub App's
  app id/private key, secret-masked to `hasSecret` — except the deliverability webhook secret, which is
  passed through unredacted, see webhook-secret-visibility-after-mint), and connections (already
  redacted by the backend before this client ever sees them).
- **Storage**: none. This client is a stateless per-call request builder (no-client-side-cache,
  stateless-module); it holds nothing in memory or on disk beyond the lifetime of a single call.
- **Transmission**: every call carries a bearer credential attached by the shared authenticated-request
  helper (session-refresh-waterfall), not by this module; a save/create/update/connect call also
  transmits whatever client secret, API key, app password, or authorization code the caller supplies,
  over whatever transport the deployment provides — this module configures no TLS or transport-level
  behavior itself.
- **Retention**: none of the secret material this module handles is retained by this module after the
  response it produced is returned to the caller; retention of the underlying credential is a backend
  concern outside this component's own source.

## Logging

Not applicable: this component contains no logging call of any kind.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/integrations/integrations.ts` and
  `wire.ts` hold the client; `integrationsApi` and the standalone OAuth-state helpers are built entirely on
  `authedJson`/`authedRequest` from `@agentic-toolkit/auth/client` (re-exported through `./http`) and `enc`
  (`encodeURIComponent`) from `./client-helpers`; `index.ts` re-exports both files as the package's public
  surface. Requirement/operation names in this recipe map onto the module's own exports as follows:
  listing providers → `listProviders`; listing/getting/saving/deleting a provider config by provider id →
  `listProviderConfigs`/`getProviderConfig`/`putProviderConfig`/`deleteProviderConfig`; creating/getting/
  updating/deleting a provider config by id → `createProviderConfig`/`getProviderConfigById`/
  `updateProviderConfig`/`deleteProviderConfigById` (their shared URL template is built by two private
  helpers, `configPath`/`configByIdPath`, see Design Decisions); testing a saved config / draft
  credentials → `testProviderConfig`/`testProviderCredentials`; transferring a config →
  `transferProviderConfig`; rotating a webhook secret → `rotateWebhookSecret`; listing/connecting/
  disconnecting/syncing/patching settings for connections → `listConnections`/`connect`/`disconnect`/
  `sync`/`patchSettings`; the OAuth/install/instance/link-token start endpoints → `getAuthUrl`/
  `getInstallUrl`/`adoptInstallations`/`registerInstance`/`createLinkToken`; the callback path/URL and
  state-claim helpers → `OAUTH_CALLBACK_PATH`/`oauthCallbackUrl`/`decodeOAuthStateClaims`/
  `isOAuthStateFresh`. Wire types referenced generically above (a "provider config record", a
  "connection record", a "test-result record", etc.) are `MaskedProviderConfig`/`SafeConnection`/
  `IntegrationTestResult`, and the connect-request's six variants are the `ConnectRequestBody`
  discriminated union; a thrown error described generically as carrying a status/code is
  `AuthHttpError`.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
