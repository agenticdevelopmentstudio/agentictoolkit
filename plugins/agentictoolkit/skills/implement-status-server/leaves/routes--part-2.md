<!-- leaf: implement-status-server/routes--part-2 · source: status-server-routes.md -->

# Status Server Routes — continued (part 2)

**Rules** (cite as `implement-status-server/routes--part-2#<slug>`):

- `config-blanket-admin-gate` MUST
- `config-peer-url-validation` MUST
- `config-peer-duplicate-detection` MUST
- `config-peer-token-redaction` MUST
- `config-mutation-reconcile-sweep` MUST
- `config-endpoint-retirement-atomicity` MUST
- `config-ignored-project-key-parsing` MUST
- `config-seed-idempotence` MUST
- `config-openapi-contract` MUST
- `cron-blanket-admin-gate` MUST
- `cron-refresh-blocking` MUST
- `cron-maintenance-bounded` MUST
- `deploy-log-unknown-id` MUST
- `deploy-log-timeout` MUST
- `deploy-log-degrade-not-error` MUST
- `deploy-log-indistinguishable-degrade` MUST
- `device-code-hashing` MUST
- `device-user-code-alphabet` MUST
- `device-user-code-normalization` MUST
- `device-start-response` MUST
- `device-token-poll-errors` MUST
- `device-token-single-use-consumption` MUST
- `device-approval-session-required` MUST
- `device-pending-lookup` MUST
- `device-approve-race-guard` MUST
- `device-deny-guarded` MUST
- `fleet-composition` MUST

### config.ts

- **config-blanket-admin-gate**: every route under this sub-app MUST require
  admin via a blanket `app.use('*', requireAdmin)` — unlike `board.ts` and
  `auto-configure.ts`, none of these mutating config endpoints is exposed at
  a shared, partially-public base path.
- **config-peer-url-validation**: a peer's `baseUrl` MUST pass
  `isValidPeerBaseUrl`, and MUST NOT resolve to this instance's own base URL
  (`assertNotSelfPeerUrl`); either failure MUST respond 400.
- **config-peer-duplicate-detection**: inserting a peer whose `baseUrl`
  duplicates an existing peer's MUST respond 409 (`isDuplicatePeerError`
  mapped to `DUPLICATE_PEER_MESSAGE`), not a raw DB constraint error.
- **config-peer-token-redaction**: every peer object returned by any route in
  this file (list, create, patch) MUST pass through `redactPeer` — the raw
  token MUST never be present in a response; a `hasToken` boolean MUST stand
  in its place.
- **config-mutation-reconcile-sweep**: every mutating route that can change
  which sites/endpoints/groups exist (creates, patches, and especially
  deletes on site-groups, sites, endpoints, and integrations) MUST inline-call
  `reconcileBoardLedger(storage, config)` with no `skipOnEmptyRoster` guard —
  these routes are the ones that CAUSE any resulting empty roster, so unlike
  `board.ts`'s reconcile route they MUST always sweep.
- **config-endpoint-retirement-atomicity**: deleting an endpoint MUST use
  `retireEndpoint`, which atomically deletes the endpoint and, if that leaves
  its parent site with no remaining endpoints, deletes the now-empty site in
  the same operation.
- **config-ignored-project-key-parsing**: `DELETE` on an ignored-project MUST
  parse a compound `platform|projectName` key from the id parameter and
  MUST respond 400 if the key does not split into exactly two non-empty
  parts.
- **config-seed-idempotence**: `POST /seed` (`runSeed`) MUST create groups,
  sites, and endpoints from the seed roster only when they do not already
  exist (matched by name), and MUST create a provider integration only when
  that provider's token environment variable is set AND no integration for
  that provider already exists — a second call with the same roster and
  environment MUST NOT create duplicates.
- **config-openapi-contract**: this file's Zod insert/patch schemas MUST stay
  in lockstep with the generated OpenAPI document that the project's own
  `openapi.test.ts` pins.

### cron.ts

- **cron-blanket-admin-gate**: `/cron/*` MUST require admin via
  `app.use('/cron/*', requireAdmin)`.
- **cron-refresh-blocking**: `POST /cron/refresh` MUST await
  `scheduler.runNow()` before responding — the caller's request does not
  complete until that refresh cycle has finished.
- **cron-maintenance-bounded**: `POST /cron/maintenance` MUST call
  `storage.maintenance.runMaintenance()` and MUST return its `done: boolean`
  verbatim; `done: false` means the prune is bounded per call and a backlog
  remains for the next invocation, not that the call failed.

### deploy-logs.ts — `GET /deployments/:id/log`

- **deploy-log-unknown-id**: an unknown deployment id MUST respond 404 before
  any provider fetch is attempted.
- **deploy-log-timeout**: the underlying provider fetch MUST be bounded by
  `LOG_TIMEOUT_MS` (25,000 ms) via `AbortController`.
- **deploy-log-degrade-not-error**: `fetchLogFor` dispatching to an
  unsupported platform, or to a platform with no configured credential, MUST
  return `null` for the log rather than throwing — the response body MUST
  still be `{ ...row, log: null }` with 200, not an error status; a genuine
  fetch failure (timeout, provider error) MUST also degrade to `log: null`
  rather than failing the whole response, since the row's own fields
  (`errorText`, summary) remain informative on their own.
- **deploy-log-indistinguishable-degrade**: the response MUST NOT
  distinguish "platform doesn't support logs" from "credential missing" from
  "provider fetch failed" — all three collapse to the same `log: null`, by
  design (the honest answer is the same either way: no log to show).

### device.ts — RFC 8628 device authorization flow

- **device-code-hashing**: both `device_code` and `user_code` MUST be stored
  only as `sha256Hex` digests; no plaintext code MUST be persisted.
- **device-user-code-alphabet**: `generateUserCode` MUST draw from
  `USER_CODE_ALPHABET`, which excludes vowels and the digits/letters
  `0`/`1`/`O`/`I`/`U`, via rejection-sampled `randomInt`, formatted as two
  groups of four (`XXXX-XXXX`).
- **device-user-code-normalization**: `hashUserCode` MUST trim and uppercase
  the input before hashing, so a user typing the code in any case or with
  incidental whitespace still matches.
- **device-start-response**: `POST /auth/device` MUST purge expired grants
  before creating a new one, MUST be rate-limited (max 10 per window), and
  MUST respond with `device_code`, `user_code`, `verification_uri`,
  `interval` (`POLL_INTERVAL_SEC` = 5), and `expires_in`
  (`DEVICE_TTL_MS` / 1000 = 900 seconds), with `Cache-Control: no-store`.
- **device-token-poll-errors**: `POST /auth/device/token` MUST be
  rate-limited (max 30 per window) and MUST map grant state to the RFC 8628
  error vocabulary: an unknown or expired code responds `{ error: 'expired'
  }` (an expired-but-still-present row MUST also be deleted at that point);
  a denied grant responds `{ error: 'denied' }`; a pending grant polled
  faster than `POLL_INTERVAL_SEC` since its last recorded poll responds
  `{ error: 'slow_down' }` WITHOUT advancing the last-poll timestamp; a
  pending grant polled at a valid interval responds
  `{ error: 'authorization_pending' }` and DOES advance the timestamp.
- **device-token-single-use-consumption**: an approved grant MUST be consumed
  atomically and exactly once (`consumeApproved`) — a second poll of an
  already-consumed grant MUST NOT re-mint or re-return the token; a
  successful consumption MUST look up the token's role and expiry and return
  the raw token value, with `Cache-Control: no-store`.
- **device-approval-session-required**: every route in `deviceApprovalRoutes`
  MUST require a session user (`requireSessionUser`) and MUST respond 403 to
  a caller with no session user — this excludes both AUTH_DISABLED anonymous
  callers and bearer-token principals from approving/denying/listing device
  grants.
- **device-pending-lookup**: `GET /auth/device/pending` MUST respond 400 if
  `user_code` is missing, MUST reap an expired grant it finds (deleting it)
  and respond 404 for it rather than returning stale pending state, and MUST
  respond 404 for any user code with no live grant.
- **device-approve-race-guard**: `POST /auth/device/approve` MUST mint the
  new token at the approver's own session tier, MUST guard the status
  transition to `approved` on the grant still being `pending` at write time,
  and — if that guard loses a race to a concurrent approve/deny — MUST
  delete the token it had just minted (no orphaned, unreachable token left
  behind) and respond 409.
- **device-deny-guarded**: `POST /auth/device/deny` MUST use the same
  guarded-transition pattern as approve, responding 404/409 under the same
  conditions.

### fleet.ts — `GET /fleet`

- **fleet-composition**: the route MUST compose `buildSnapshot` (from
  `reads.ts`) with `assembleFleet` (from `../peers/fleet`) and MUST return the
  assembled fleet-member list as its sole responsibility — it holds no
  independent business logic of its own.

