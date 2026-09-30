<!-- leaf: implement-hub-domain-1/integrations--part-2 · source: hub-domain-integrations.md -->

# Hub Domain: Integrations — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/integrations--part-2#<slug>`):

- `provider-catalog-fetch` MUST
- `provider-config-list` MUST
- `provider-config-get-by-provider-id` MUST
- `provider-config-get-not-found-null` MUST
- `provider-config-put-preserves-blank-secret` MUST
- `provider-config-delete-by-provider-id` MUST
- `provider-config-create` MUST
- `provider-config-get-by-id` MUST
- `provider-config-get-by-id-not-found-null` MUST
- `provider-config-update-by-id` MUST
- `provider-config-delete-by-id` MUST
- `provider-config-two-address-schemes-share-a-url-shape` MUST
- `test-saved-config` MUST
- `test-saved-config-github-app-also-connects` MUST
- `test-result-ok-false-is-not-an-error` MUST
- `test-draft-credentials-writes-nothing` MUST
- `test-draft-credentials-with-stored-secret` MUST
- `transfer-request-shape` MUST
- `transfer-moves-credential-connections-and-caches-together` MUST
- `transfer-mints-new-rdid` MUST
- `transfer-connections-count-is-live-only` MUST
- `rotate-webhook-secret-request-shape` MUST
- `rotate-webhook-secret-is-destructive` MUST
- `rotate-webhook-secret-also-generates-first-secret` MUST
- `connections-list-scoped-by-ecosystem` MUST
- `connect-request-shape` MUST
- `connect-every-variant-names-ecosystem` MUST
- `connect-github-app-has-no-code` MUST
- `connect-app-password-source-exclusivity-delegated` MUST
- `disconnect-request-shape` MUST
- `sync-request-shape` MUST
- `sync-no-worker-throws-503` MUST
- `patch-settings-request-shape` MUST

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
