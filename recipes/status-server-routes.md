---
id: 77587f0b-5a27-44d9-a507-46bb90c9046a
title: Status Server Routes
domain: agentictoolkit://recipes/status-server-routes
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The 17 Hono/OpenAPIHono route modules under status-server/src/routes — activity
  feed, auth, auto-configure, badge, board, config, cron, deploy-logs, device authorization,
  fleet, deploy webhooks, the shared body-validation helper, the read-side snapshot/live/history
  API, SSE streaming, telemetry, API tokens, and user administration.
platforms:
- typescript
- web
tags:
- routing
- http-api
- authentication
- authorization
- webhooks
- server-sent-events
- rate-limiting
- validation
- device-flow
- pagination
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/pagination
- agenticdevelopercookbook://guidelines/implementing/networking/real-time-communication
- agenticdevelopercookbook://guidelines/implementing/networking/rate-limiting
- agenticdevelopercookbook://guidelines/implementing/security/authentication
- agenticdevelopercookbook://guidelines/implementing/security/token-handling
- agenticdevelopercookbook://guidelines/implementing/testing/testing
related:
- agentictoolkit://recipes/status-server-board
approved-by: ''
approved-date: ''
references: []
---

# Status Server Routes

## Overview

`status-server-routes` is the HTTP surface of the status server: 17 route
modules under `packages/web/packages/status-server/src/routes/`, each a
factory that returns a `Hono` (or `OpenAPIHono`) sub-app mounted by the
top-level server assembly. Together they cover four bands: public
pre-authentication endpoints (`auth.ts`, `device.ts`'s public half, provider
webhooks in `hooks.ts`), authenticated read endpoints that assemble the
dashboard's live/status/snapshot/history/telemetry views (`reads.ts`,
`stream.ts`, `telemetry.ts`, `activity.ts`, `fleet.ts`, `badge.ts`), authenticated
write endpoints that mutate the monitored roster or the instance's
users/tokens (`config.ts`, `board.ts`'s reconcile route, `auto-configure.ts`,
`cron.ts`, `users.ts`, `tokens.ts`, `device.ts`'s approval half), and one
shared low-level helper (`read-body.ts`). None of these files render UI —
they are server-side request handlers whose contract is the JSON (or SSE, or
SVG) they emit, not a screen.

Route modules delegate policy to lower layers rather than re-implementing it:
persistence and atomic guards live behind the `Storage` port, roster-vs-board
folding lives in `reconcileBoardLedger`/`deriveBoard` (documented in the
sibling `status-server-board` recipe), and project-matching/wiring for
auto-configure lives in the external `@agentic-toolkit/deploy-platform/engine`
package. This recipe documents the route layer's own contract: what each
endpoint validates, what it returns, what authorization tier gates it, and
where its error/edge-case behavior is and isn't defined.

## Behavioral Requirements

### activity.ts — `GET /activity`

- **activity-cursor-pairing**: `before` (an ISO-parseable timestamp) and
  `beforeId` MUST be supplied together; supplying only one of the pair MUST
  respond 400.
- **activity-cursor-empty-id-allowed**: an empty-string `beforeId` paired with
  a non-empty `before` MUST be accepted — it is the stall-escape cursor that
  `pageActivity` itself mints when a page boundary lands mid-timestamp-tie; an
  empty-string `before` MUST NOT be accepted (it is not a valid ISO
  timestamp) and MUST respond 400.
- **activity-cursor-range-check**: the parsed cursor timestamp MUST be a safe
  integer in `[0, MAX_CURSOR_MS]` (`MAX_CURSOR_MS = 8.64e15`, the largest
  timestamp `Date` can represent); a cursor outside that range or that fails
  to parse MUST respond 400.
- **activity-limit-clamping**: an absent, non-numeric, or out-of-range
  `limit` query parameter MUST fall back to `MAX_ACTIVITY_ROWS`; a numeric
  `limit` MUST be clamped into `[1, MAX_ACTIVITY_ROWS]` rather than rejected.
- **activity-cold-path**: this route reads via `createActivityPageReader`
  against persisted rows only; it is not on the SSE live-update path, and a
  client polls it explicitly for history beyond the board's live tail.

### auth.ts — `authRoutes`

- **auth-pre-seam-mounting**: `authRoutes` are documented as mounted BEFORE
  the app-wide `requireAuth` seam — every route here MUST be reachable
  without a session or bearer token.
- **auth-signup-normalization**: `POST /auth/signup` MUST lowercase the
  submitted email before any existence check or insert.
- **auth-signup-duplicate-detection**: signup MUST respond 409 both when a
  pre-check finds an existing user for the normalized email, and when the
  insert itself fails a unique constraint (`isUniqueViolation`) — the second
  path exists because the pre-check and insert are not one atomic step, so a
  concurrent signup race MUST still surface as 409, not a 500 or a silent
  duplicate.
- **auth-login-timing-safety**: `POST /auth/login` MUST run `verifyPassword`
  against a real stored hash when the user exists, and against
  `DUMMY_PASSWORD_HASH` when the user does not exist, so that an unknown
  email and a known email with a wrong password take a comparable code path;
  both failure cases MUST respond 401 with the same message.
- **auth-logout-dual-revocation**: `POST /auth/logout` MUST revoke a bearer
  token when the `Authorization` header carries one with the `sts_` API-token
  prefix, AND MUST revoke/clear the session cookie when one is present; it
  MUST respond 200 `{ ok: true }` regardless of which credential (or neither)
  was present.
- **auth-me-never-unauthenticated**: `GET /auth/me` MUST NOT respond 401
  under any input; it MUST resolve a session first, fall back to a bearer
  token's principal shape second, and otherwise respond 200 with
  `{ user: null }`.
- **auth-rate-limits**: `/auth/login` MUST be rate-limited (max 10 per
  window) and `/auth/signup` MUST be rate-limited (max 5 per window),
  independently of each other.
- **auth-oauth-mounting**: `authRoutes` MUST mount `githubRoutes` at its own
  root so GitHub OAuth callback handling shares the same pre-seam exposure.

### auto-configure.ts — `POST /auto-configure`

- **auto-configure-admin-gate**: the route MUST require admin per-route
  (`requireAdmin` applied to this one route, not via a blanket `app.use('*')`
  as `config.ts`/`users.ts` do) because this sub-app is mounted alongside
  other, non-admin routes at the same base path.
- **auto-configure-opt-out-respected**: a project already recorded as an
  ignored project (matched by platform+projectName) MUST be excluded from
  matching/creation on this and every subsequent call until explicitly
  un-ignored.
- **auto-configure-ignore-persistence**: entries in the request's `ignore`
  array MUST be persisted (step 1) before matching/creation runs, so a
  project ignored in the same request that also appears elsewhere in the
  payload is honored within that same call.
- **auto-configure-create-target-validation**: a non-null `create` object
  MUST validate `groupId` (required) and `forceGroup` (optional boolean) via
  `autoConfigureBody`; a missing or malformed `create` MUST respond 400.
- **auto-configure-lite-adapter**: `performAutoConfigure` MUST talk to
  persistence exclusively through `statusAdapter` — a direct, in-process
  `StatusAddApi` implementation backed by `storage.config` calls (not an HTTP
  round-trip) — keeping the matching/creation engine itself HTTP-agnostic and
  reusable outside this route.
- **auto-configure-site-purge-on-delete**: `statusAdapter.deleteSite` MUST
  use the purging delete (removing the site's endpoints with it), not a
  bare row delete, so a re-run never leaves orphaned endpoints under a
  deleted site.
- **auto-configure-skip-dedup**: repeated skip entries for the same
  project+reason MUST be deduplicated in the response's `skippedDetail`
  while preserving first-seen order; the `skipped` count itself MUST NOT be
  deduplicated (it reflects every skip event, not distinct reasons).
- **auto-configure-reconcile-sweep**: successful creation/wiring MUST trigger
  a board-ledger reconcile so the board reflects newly-added sites/endpoints
  without waiting for the next scheduled cycle.
- **auto-configure-partial-failure**: a run is not transactional. Per-project failures on the project axis (`runAutoConfigure`) and per-endpoint failures on the endpoint axis (`wireMatchingEndpoints`) are caught one item at a time and reported in `skipped`/`skippedDetail` with the error message as the reason, while every other item still proceeds and earlier writes stay committed. When a created site's endpoint insert fails, the engine deletes that site so its (group, slug) cannot 409 later runs; a failed rollback delete is not reported separately, and the original error is what lands in `skippedDetail`. A storage failure in the ignore persist, enumeration or classify steps is not caught and fails the whole request, with any ignores already written left in place.

### badge.ts — `GET /status/badge.svg`

- **badge-overall-remapping**: the route MUST re-expand the compact
  snapshot's 3-state `overall` (`healthy`/`degraded`/`down`) to the 4-state
  `OverallStatus` vocabulary used elsewhere (`operational`/`degraded`/
  `major_outage`, plus `unknown`) via `overallFromSnapshot` before rendering.
- **badge-error-fallback**: any failure while building the underlying
  snapshot MUST be caught and MUST fall back to rendering the badge with
  `overall = 'unknown'` rather than propagating an error response — a status
  badge embedded in a third-party README MUST always render an SVG, never a
  5xx.
- **badge-caching**: the response MUST carry `Cache-Control: public,
  max-age=60`.
- **badge-svg-shape**: the SVG MUST be built via `buildSvg` in the
  shields.io label/value badge style, keyed off the remapped overall status.

### board.ts

- **board-read-always-fresh**: `GET /board` MUST derive its response fresh on
  every call (`deriveBoard(await readBoardFacts(...), nowMs)`) rather than
  serving a cached board — it is the client's sole source for the current
  Problems list, Activity tail, and top-level indicator, so staleness here
  would directly mislead the dashboard.
- **board-reconcile-admin-gate**: `POST /board/reconcile` MUST require admin,
  applied per-route (matching `auto-configure.ts`'s rationale, not a blanket
  `app.use('*')`).
- **board-reconcile-skip-on-empty-roster**: the reconcile call MUST pass
  `skipOnEmptyRoster: true` so an empty monitored roster (e.g. mid-migration,
  or a fresh instance) is treated as "nothing to reconcile" rather than as
  "everything just went down."
- **board-reconcile-idempotent**: repeated calls with no roster/status change
  between them MUST produce no additional opened/resolved transitions —
  the route is documented as safe to call repeatedly (e.g. from a manual
  admin action or a retry).
- **board-reconcile-can-alert**: the route MUST be treated as capable of
  synchronously triggering on-call alerting (open/recovered transitions) on
  the request thread — a caller MUST NOT assume this endpoint is read-only or
  side-effect-free.

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

### hooks.ts — provider deploy webhooks

- **hooks-pre-seam-mounting**: provider webhook ingest routes MUST be mounted
  before the app-wide `requireAuth` seam — a provider cannot present a
  session cookie or bearer token, so authentication here is the signature
  check, not the seam.
- **hooks-ownership-three-way**: `ownedBySite` MUST return one of
  `'owned'`, `'not-owned'`, or `'unknown'` — never collapse to a boolean —
  and MUST return `'unknown'` (logging the underlying error) rather than
  throwing when the roster read itself fails, so the caller can fail closed.
- **hooks-fail-closed-on-unknown-ownership**: both webhook handlers MUST
  respond 503 when ownership resolves to `'unknown'`, MUST respond 200 with
  `{ ok: true, ignored: 'not owned by a site' }` when it resolves to
  `'not-owned'`, and MUST proceed to persist only on `'owned'`.
- **hooks-signature-before-parse**: `POST /hooks/vercel` MUST read the raw
  request body as text and verify the HMAC-SHA1 signature
  (`verifyVercelSignature`) BEFORE attempting to JSON-parse it; a bad
  signature MUST respond 401 and MUST NOT parse the body at all.
- **hooks-secret-unconfigured**: either webhook route MUST respond 503 if its
  verification secret is not configured, rather than accepting an
  unverifiable payload.
- **hooks-unparseable-avoids-retry-storm**: a JSON parse failure on a
  signature-valid Vercel payload MUST respond 200 with `{ ok: true, ignored:
  'unparseable' }`, not an error status — an error status would make the
  provider retry a payload that will never parse.
- **hooks-unmapped-event-ignored**: a well-formed payload whose event type
  has no mapping (`mapVercelDeployEvent`/`mapRailwayDeployEvent` returning
  null) MUST respond 200 with `{ ok: true, ignored: true }`.
- **hooks-railway-shared-secret**: `POST /hooks/railway` MUST accept the
  shared secret via either a `?token=` query parameter OR an
  `x-webhook-secret` header (`verifySharedSecret`), and MUST respond 401 if
  neither matches.
- **hooks-persist-fail-soft**: a persistence failure
  (`storage.deploy.upsertDeployments`) on an otherwise-owned, verified event
  MUST be caught and logged, MUST NOT fail the webhook response, and MUST
  NOT prevent the event from being pushed to the live buffer — the poll
  cycle and buffer together cover a lost persist.
- **hooks-derivation-fail-soft**: `runReconcile`'s call into
  `reconcileBoardLedger`/alert-flushing MUST be caught and logged; a
  derivation failure MUST NOT turn a successfully-verified, successfully-
  persisted webhook into an error response.
- **hooks-reconcile-single-flight-coalescing**: `reconcileGate` MUST ensure
  at most one reconcile pass runs at a time per `hooksRoutes` instance, and
  MUST coalesce concurrent arrivals during a running pass so that every
  arrival is covered by either the in-flight pass or one guaranteed
  follow-up pass (the "cleared before the pass" queued-flag pattern) —
  never dropped.
- **hooks-live-buffer-and-broadcast**: a successfully-owned event MUST be
  pushed onto the live update buffer and MUST trigger `emitLiveUpdate` so
  subscribed SSE clients see it without waiting for their next poll.
- **hooks-cloudflare-absence-is-deliberate**: the absence of a
  `/hooks/cloudflare` route is a documented, pre-approved decision (source
  comment: `adh-ui-allow: defer — Cloudflare has no per-deploy webhook;
  polling covers it; approved by mike 2026-06-26`), not an oversight —
  Cloudflare deploy status is covered by the existing poll cycle instead.

### read-body.ts

- **read-body-canonical-helper**: `readValidatedBody<T>(c, schema)` MUST be
  the one shared JSON-read-and-Zod-validate helper for new route code; a
  JSON parse failure MUST respond 400 with an `'invalid JSON'`-style message,
  and a schema validation failure MUST respond 400 with a message that
  includes the Zod issue detail.
- **read-body-partial-adoption**: this helper is documented as replacing
  three near-identical `parse`/`parseBody`/`readJson` variants that had
  drifted across the route files; as of these 17 files, `device.ts` and
  `tokens.ts` use it, while `auth.ts` and `config.ts` retain their own local,
  behaviorally-equivalent copies rather than having been migrated onto it —
  this is a recorded fact about the current codebase, not a behavioral
  inconsistency (all variants still produce an equivalent 400 on bad input).

### reads.ts — the read-side snapshot/live/history API

- **reads-live-owner-bound-first**: `buildLiveSnapshot` MUST resolve
  `owners`/`projects` via board ownership BEFORE running the deploy query, so
  the deploy query is bounded to owned projects rather than scanning
  unbounded provider history.
- **reads-live-buffer-overlay**: `deploymentDtos` MUST merge persisted rows
  with the in-memory live-buffer webhook overlay by id, with the buffer's
  version winning the merge for any id present in both — a webhook that
  arrived after the last DB read must not be shadowed by a stale persisted
  row.
- **reads-problems-single-producer**: `boardProblems` MUST be the sole
  producer of the derived Problems list used across `/live`, `/status`, and
  `/snapshot`; a documented decision explicitly rejects splitting out a
  cheaper "problems-only" path to avoid two divergent derivations of the
  same list.
- **reads-snapshot-error-redaction**: `buildSnapshot`'s `problems` list MUST
  exclude any Problem whose `target` parses as an error target
  (`parseErrorsTarget(p.target) !== null`) — error Problems carry internal
  GlitchTip project identifiers and exception titles in their `name`/`detail`
  that MUST NOT reach `/public/status-summary`'s anonymous readers; this
  filter is documented as a deliberate, reversible disclosure decision, not
  an incidental omission.
- **reads-deploy-cache-atomicity**: `refreshAndEnumerateDeployProjects` MUST
  treat "refresh provider data" and "enumerate projects from it" as one
  inseparable, cached unit (`PROVIDER_READ_CACHE_MS` = 30,000 ms); a Vercel
  read failure during refresh MUST fail the whole call closed rather than
  returning a partially-refreshed enumeration.
- **reads-deploy-projects-shared-cache**: `GET /deploy-projects` MUST share
  its cache across concurrent callers via `cachedSingleFlight`, and MUST
  bypass the cache only when `?fresh=1` is supplied.
- **reads-history-slug-required**: `GET /history` MUST respond 400 if no
  `slug` query parameter is supplied.
- **reads-history-hours-clamp**: `GET /history`'s `hours` parameter MUST be
  clamped to `[1, 168]`.
- **reads-uptime-days-clamp**: `GET /uptime`'s `days` parameter MUST be
  clamped to `[1, 365]`.
- **reads-response-history-clamps**: `GET /response-history`'s `hours`
  parameter MUST be clamped to `[1, 2160]` and its `buckets` parameter MUST
  be clamped to `[1, 240]`.
- **reads-endpoint-wiring-paused-claims**: `listEndpointsForWiring` MUST
  include paused endpoints, not only active ones (it deliberately is not
  `listActiveEndpoints`) — a paused monitor still claims its project for
  wiring/correlation purposes so re-enabling it does not silently create a
  duplicate wiring.
- **reads-correlate-ignore-vs-wire-granularity**: `correlateDeployProjects`
  MUST treat "ignored" as project-level and "wired" as per-environment
  (keyed by `deployTargetKey`), with a Railway host-membership fallback when
  an exact target key does not match.

### stream.ts — SSE and manual-check trigger

- **stream-opening-frame**: `GET /live/stream` MUST reuse a snapshot built
  within the last `OPENING_CACHE_MS` (1,500 ms) if one exists, and otherwise
  build a fresh one for the opening frame; a build failure for the opening
  frame MUST be caught and MUST send a null-data opening frame rather than
  failing the stream's setup.
- **stream-subscribe-before-send**: the route MUST call `subscribeLive`
  BEFORE sending the opening frame, closing the race window in which an
  update could arrive between "snapshot taken" and "subscribed" and be
  missed entirely.
- **stream-heartbeat**: the stream MUST send a heartbeat (`: ping`) every
  `HEARTBEAT_MS` (25,000 ms) to keep intermediary proxies from closing an
  idle connection.
- **stream-lifetime-cap**: the stream MUST be forcibly closed after
  `STREAM_MAX_MS` (600,000 ms / 10 minutes), requiring the client to
  reconnect — this bounds how long a revoked session's credential can keep
  streaming after revocation.
- **stream-cleanup-idempotent**: cleanup (unsubscribe, clear heartbeat/cap
  timers) MUST run exactly once per connection regardless of which of
  `cancel()`, an `enqueue` failure, or the request's `abort` signal triggers
  it first.
- **stream-check-requires-scheduler**: `POST /live/check` MUST respond 503 if
  no scheduler is configured.
- **stream-check-debounce**: `POST /live/check` MUST debounce per caller
  (session user id, or `'anon'`) using `MANUAL_MIN_MS` (3,000 ms); a call
  within the floor MUST respond `{ ok: true, ran: false, reason: 'debounced'
  }` and MUST NOT update the throttle timestamp or trigger a cycle.
- **stream-check-detached**: a call past the debounce floor MUST trigger the
  cycle via `scheduler.runNowDetached()` — fire-and-forget, NOT awaited —
  in explicit contrast to `cron.ts`'s `POST /cron/refresh`, which awaits
  `scheduler.runNow()`; this is a documented inconsistency between the two
  "trigger a cycle now" routes, not a shared contract.
- **stream-check-test-reset-hook**: `resetCheckThrottle()` MUST be exported
  as a test-only hook to clear the process-global debounce map between test
  cases.

### telemetry.ts

- **telemetry-injectable-fetchers**: `telemetryRoutes` MUST accept optional
  `deps.errorsFetcher`/`deps.analyticsFetcher`, defaulting to
  `buildErrorsFetcher`/`buildAnalyticsFetcher` built from `config` when not
  supplied, so tests can substitute fetchers without varying global state.
- **telemetry-last-good-fallback**: a failed poll of one provider MUST serve
  that stream's last successfully-polled value (or an empty list on a cold
  start with no prior success) rather than blanking it, and MUST NOT affect
  the other stream's value.
- **telemetry-single-flight-cache**: `GET /telemetry` MUST share a
  `CACHE_TTL_MS` (30,000 ms) single-flight cache across concurrent callers;
  `?fresh=1` MUST bypass a cached-but-not-in-flight result but MUST still
  join an already-in-flight build rather than starting a second one.
- **telemetry-no-store**: `GET /telemetry`'s response MUST carry
  `Cache-Control: no-store`.
- **telemetry-db-backed-endpoints**: `GET /errors` and `GET /analytics` MUST
  read from `storage.telemetry.errors.load()` / `storage.telemetry.analytics
  .load()` (SQLite-backed, not a live provider poll) and MUST carry
  `Cache-Control: public, max-age=30`.
- **telemetry-analytics-latest-reduction**: `GET /analytics` MUST reduce the
  stored rows to the latest value per `(metric, window, scope)` triple before
  responding.
- **telemetry-peer-token-excluded**: none of this file's routes MUST accept
  `PEER_TOKEN` as a valid credential — peers exchange health snapshots
  (`/snapshot`), not telemetry, and this file is explicitly excluded from
  that exchange.

### tokens.ts — API token management

- **tokens-mint-requires-session-admin**: `POST /tokens` MUST require both
  `requireAdmin` AND a session `user` (`c.get('user')`) — `requireAdmin`
  alone also admits an admin bearer token and, under AUTH_DISABLED, an
  anonymous admin, but neither of those has an honest `created_by`, so both
  MUST respond 403 here even though `requireAdmin` would otherwise pass
  them.
- **tokens-mint-raw-once**: the raw token value MUST be returned exactly once,
  in the create response, with `Cache-Control: no-store`; it MUST NOT be
  retrievable from `GET /tokens` afterward.
- **tokens-list-no-store**: `GET /tokens` MUST carry `Cache-Control:
  no-store`.
- **tokens-delete-self-or-admin**: `DELETE /tokens/:id` MUST NOT be gated by
  the `requireAdmin` middleware; it MUST instead allow the call when the
  caller's tier is `'admin'` OR the caller's own token id equals the target
  id, and MUST respond 403 otherwise — a token MUST be able to revoke
  itself regardless of its own role.
- **tokens-delete-not-found**: revoking an id with no matching token MUST
  respond 404; a successful revoke MUST respond 204 with no body.

### users.ts — user administration

- **users-blanket-admin-gate**: every route MUST require admin via
  `app.use('*', requireAdmin)`.
- **users-role-body-validation**: `PATCH /users/:id`'s body MUST validate
  against `roleBody` (`role` in `pending`/`viewer`/`admin`); invalid JSON
  MUST respond 400 `'Invalid JSON'` and a role outside the enum MUST respond
  400 `'Invalid role'`.
- **users-last-admin-guard-atomic**: role changes MUST go through
  `setUserRoleGuarded`, whose guard is inside the write statement itself
  (not a preceding read) specifically to prevent two concurrent demotes of
  two different admins from both succeeding and leaving zero admins;
  `undefined` MUST map to 404, `'blocked'` MUST map to 409 `'Cannot demote
  the last admin'`.
- **users-delete-last-admin-guard-atomic**: `DELETE /users/:id` MUST use the
  same atomic-guard pattern via `deleteUserGuarded`; `false` MUST map to 404,
  `'blocked'` MUST map to 409 `'Cannot delete the last admin'`.
- **users-post-seam-mounting**: this sub-app is documented as mounted after
  the `requireAuth` seam and, within these files, after the device-approval
  trio in `device.ts`.

## Appearance

Not applicable — this is a set of HTTP route handlers, not a visual component.

## States

Not applicable — this is a set of HTTP route handlers, not a visual component.

## Accessibility

Not applicable — this is a set of HTTP route handlers, not a visual component.

## Conformance Test Vectors

| # | Input / Action | Expected Output / Effect | Requirement(s) |
|---|---|---|---|
| 1 | `GET /activity?before=2026-01-01T00:00:00Z` with no `beforeId` | 400 | activity-cursor-pairing |
| 2 | `GET /activity?before=2026-01-01T00:00:00Z&beforeId=` | 200, treated as the stall-escape cursor | activity-cursor-empty-id-allowed |
| 3 | `GET /activity?before=&beforeId=abc` | 400 (empty `before` is not a valid timestamp) | activity-cursor-empty-id-allowed |
| 4 | `GET /activity?limit=999999` | limit clamped to `MAX_ACTIVITY_ROWS` | activity-limit-clamping |
| 5 | `POST /auth/signup` with an email already registered under a different case | normalized to lowercase, 409 | auth-signup-normalization, auth-signup-duplicate-detection |
| 6 | Two concurrent `POST /auth/signup` for the same new email | one 201, the other 409 via unique-violation mapping | auth-signup-duplicate-detection |
| 7 | `POST /auth/login` for an email that does not exist | `verifyPassword` still runs (against `DUMMY_PASSWORD_HASH`), 401 | auth-login-timing-safety |
| 8 | `GET /auth/me` with no cookie and no bearer token | 200 `{ user: null }`, never 401 | auth-me-never-unauthenticated |
| 9 | `POST /auto-configure` whose `create.groupId` is missing | 400 | auto-configure-create-target-validation |
| 10 | Auto-configure creates a site whose paired endpoint creation then throws | engine rolls back the just-created site (per `auto-configure.int.test.ts`'s "rolls back the just-created site when its endpoint fails to create (no orphan)"); `listSites()`/`listEndpoints()` both empty afterward | auto-configure-lite-adapter |
| 11 | `buildSnapshot` throws while assembling `/status/badge.svg` | 200 SVG rendered with `overall: 'unknown'`, no error response | badge-error-fallback |
| 12 | `GET /board` called twice with no intervening roster or check change | identical derived board both times, freshly derived each call | board-read-always-fresh |
| 13 | `POST /board/reconcile` with an empty monitored roster | reconcile reports skipped rather than mass-opening issues | board-reconcile-skip-on-empty-roster |
| 14 | `POST /config/peers` with `baseUrl` equal to this instance's own base URL | 400 | config-peer-url-validation |
| 15 | `POST /config/peers` with a `baseUrl` matching an existing peer | 409 | config-peer-duplicate-detection |
| 16 | `GET /config/peers` | every peer object has `hasToken` and no `token` field | config-peer-token-redaction |
| 17 | `DELETE /config/endpoints/:id` on the last endpoint of its site | endpoint and now-empty site both removed atomically | config-endpoint-retirement-atomicity |
| 18 | `POST /config/seed` called twice against the same environment | second call creates no duplicate groups/sites/endpoints/integrations | config-seed-idempotence |
| 19 | `GET /deployments/:id/log` for a Cloudflare-platform deployment (unsupported) | 200, `log: null` | deploy-log-degrade-not-error |
| 20 | `GET /deployments/:id/log` whose provider fetch exceeds `LOG_TIMEOUT_MS` | 200, `log: null` (aborted, not surfaced as an error) | deploy-log-timeout, deploy-log-degrade-not-error |
| 21 | `POST /auth/device/token` polled twice within `POLL_INTERVAL_SEC` of each other while pending | second call `{ error: 'slow_down' }`, last-poll timestamp unchanged | device-token-poll-errors |
| 22 | `POST /auth/device/token` polled twice after approval | first call returns the token, second call does not re-return it (already consumed) | device-token-single-use-consumption |
| 23 | Two concurrent `POST /auth/device/approve` for the same user code | one succeeds, the other's guarded update loses the race, its freshly-minted token is deleted, 409 | device-approve-race-guard |
| 24 | `GET /auth/device/pending?user_code=` omitted | 400 | device-pending-lookup |
| 25 | `POST /hooks/vercel` with a body that fails HMAC verification | 401, body never parsed | hooks-signature-before-parse |
| 26 | `POST /hooks/vercel` with a valid signature but unparseable JSON | 200 `{ ok: true, ignored: 'unparseable' }` | hooks-unparseable-avoids-retry-storm |
| 27 | `POST /hooks/vercel` for a project the roster does not own, roster lookup itself fails | 503 (`unknown` ownership, fail-closed) | hooks-fail-closed-on-unknown-ownership |
| 28 | `POST /hooks/railway` with neither `?token=` nor `x-webhook-secret` set correctly | 401 | hooks-railway-shared-secret |
| 29 | A burst of webhook calls arriving while a reconcile pass is already running | at most one pass in flight; every arrival covered by that pass or one guaranteed follow-up | hooks-reconcile-single-flight-coalescing |
| 30 | `GET /status/snapshot` when an error-type Problem is currently open | that Problem excluded from the response's `problems` array | reads-snapshot-error-redaction |
| 31 | `GET /history` with no `slug` | 400 | reads-history-slug-required |
| 32 | `GET /deploy-projects` called by three concurrent callers with no `?fresh=1` | one underlying provider refresh, three callers share its result | reads-deploy-projects-shared-cache |
| 33 | `POST /live/check` called twice within `MANUAL_MIN_MS` by the same session user | second call `{ ok: true, ran: false, reason: 'debounced' }`, no second cycle triggered | stream-check-debounce |
| 34 | `POST /live/check` vs. `POST /cron/refresh` | the former does not await the triggered cycle (`runNowDetached`), the latter does (`runNow`) | stream-check-detached, cron-refresh-blocking |
| 35 | `GET /live/stream` open for longer than `STREAM_MAX_MS` | connection force-closed, client must reconnect | stream-lifetime-cap |
| 36 | `GET /telemetry` when the analytics provider poll fails but the errors provider poll succeeds | response has a fresh `errors` array and the last-good (or empty) `analytics` array — neither stream is blanked by the other's failure | telemetry-last-good-fallback |
| 37 | `POST /tokens` called by an AUTH_DISABLED anonymous admin (no session user) | 403 | tokens-mint-requires-session-admin |
| 38 | `DELETE /tokens/:id` called by a non-admin token whose id equals `:id` | allowed (self-revoke) | tokens-delete-self-or-admin |
| 39 | `DELETE /tokens/:id` called by a non-admin token whose id differs from `:id` | 403 | tokens-delete-self-or-admin |
| 40 | Two concurrent `PATCH /users/:id` demoting two different admins, leaving one admin total between them | at most one demote succeeds; the one that would leave zero admins responds 409 | users-last-admin-guard-atomic |

## Edge Cases

- **Null/empty input**: an empty-string `beforeId` is a valid activity
  cursor half; an empty-string `before` is not (activity.ts). An empty JSON
  body on any `readValidatedBody`/`readJson`/`parseBody` call responds 400
  rather than being treated as `{}`.
- **Boundary values**: `MAX_CURSOR_MS` (`8.64e15`) is the largest timestamp a
  cursor may carry; `history`/`uptime`/`response-history` each clamp rather
  than reject an out-of-range `hours`/`days`/`buckets` value; rate-limit
  windows (`max: 10`/`5`/`30`) and TTLs (`DEVICE_TTL_MS`, `TOKEN_TTL_MS`,
  `CACHE_TTL_MS`, `PROVIDER_READ_CACHE_MS`) are the concrete numeric edges a
  test should probe at ±1.
- **Concurrent access**: the reconcile-gate coalescing in `hooks.ts`, the
  device-approval/deny race guard in `device.ts`, the last-admin-guard race
  in `users.ts`, and the signup unique-violation race in `auth.ts` are all
  places where two nearly-simultaneous requests are expected and handled —
  each has an atomic guard at the write, not a read-then-write check.
  `telemetry.ts`'s single-flight cache and `reads.ts`'s deploy-projects
  single-flight cache are the read-side analog: concurrent callers share one
  underlying fetch rather than each triggering their own.
- **Error states**: the 503-vs-401-vs-409 pattern is consistent across files
  for a specific reason each time — 503 means "we cannot answer honestly
  right now" (hooks.ts's unknown ownership, device.ts's missing scheduler in
  stream.ts, deploy-logs' provider misconfiguration folding into a null log
  rather than 503), 401 means "the credential itself is invalid" (hooks.ts's
  signature check, auth.ts's login), and 409 means "the state you're trying
  to create conflicts with what's already there" (signup/peer duplicates,
  last-admin guards, device-approval races).
- **Offline/disconnected**: `stream.ts`'s SSE cleanup runs identically
  whether the client disconnects (`cancel()`), the connection's `abort`
  signal fires, or an `enqueue` fails outright — three different disconnect
  signals converge on the same idempotent cleanup path. `reads.ts`'s
  `refreshAndEnumerateDeployProjects` and `telemetry.ts`'s fetchers both fail
  closed or fall back to last-good data rather than surfacing a raw network
  error to the caller when an upstream provider is unreachable.

## Configuration

| Name | Source file | Purpose |
|---|---|---|
| `storage: Storage` | most route factories | persistence port passed into every route factory |
| `config: StatusConfig` | config.ts, telemetry.ts, reads.ts, hooks.ts | webhook secrets, peer/self base URL, provider credentials |
| `scheduler?: Scheduler` | cron.ts, stream.ts | optional — `runNow`/`runNowDetached`; its absence 503s `POST /live/check` |
| `deps.errorsFetcher` / `deps.analyticsFetcher` | telemetry.ts | test-injection points overriding the default provider fetchers |
| `SeedRoster` | config.ts | roster consumed by `runSeed` for `POST /config/seed` |
| `MAX_ACTIVITY_ROWS` | activity.ts (imported) | default/clamp ceiling for `limit` |
| `MAX_CURSOR_MS = 8.64e15` | activity.ts | largest timestamp a cursor may carry |
| `DEVICE_TTL_MS = 900_000` | device.ts | device/user code grant lifetime (15 min) |
| `POLL_INTERVAL_SEC = 5` | device.ts | minimum seconds between token polls before `slow_down` |
| `TOKEN_TTL_MS = 2_592_000_000` | device.ts | minted device-flow token lifetime (30 days) |
| `LOG_TIMEOUT_MS = 25_000` | deploy-logs.ts | provider build-log fetch abort timeout |
| `HEARTBEAT_MS = 25_000` | stream.ts | SSE keep-alive ping interval |
| `MANUAL_MIN_MS = 3_000` | stream.ts | per-caller manual-check debounce floor |
| `OPENING_CACHE_MS = 1_500` | stream.ts | reuse window for a recent snapshot as the SSE opening frame |
| `STREAM_MAX_MS = 600_000` | stream.ts | forced SSE reconnect interval (10 min) |
| `CACHE_TTL_MS = 30_000` | telemetry.ts | single-flight cache TTL for `/telemetry` |
| `PROVIDER_READ_CACHE_MS = 30_000` | reads.ts | single-flight cache TTL for deploy-project enumeration |
| `MAX_DEPLOYS = 250` | reads.ts | cap on deployments assembled per snapshot |
| `RESPONSE_BUCKETS = 60` | reads.ts | default bucket count for response-time history |
| rate limits (`max: 10/5/30`) | auth.ts, device.ts | per-route request-rate ceilings via the `rateLimit` middleware |

## Deep Linking

`POST /auth/device` constructs a `verification_uri` that a client renders as
a link (or QR code) to complete the device-authorization flow in a browser;
this is the one place in these 17 files that manufactures a URL meant to be
followed by a human outside the calling client. No other route in this
component constructs or consumes a deep link — the remaining 16 files are
JSON/SSE/SVG APIs with no link surface.

## Localization

None of these routes look up a translation table; every user-facing message
is a hardcoded English string baked into the `HTTPException`/response body,
for example: `'Invalid JSON'`, `'Invalid role'`, `'Cannot demote the last
admin'`, `'Cannot delete the last admin'`, `'An account with this email
already exists'` (auth.ts), `'user_code is required'` (device.ts),
`DUPLICATE_PEER_MESSAGE` (config.ts), `'Admin required'` / `'token not
found'` (tokens.ts), and `badge.ts`'s shields-style label vocabulary
(`'status'` plus the remapped overall value). This is a fact about the
current source, not a gap: these are internal/operator- and integrator-
facing strings (webhook responses, admin API errors, a CI badge), not
end-user application copy, and none of the 17 files reads a locale or
translation resource.

## Accessibility Options

Not applicable: these are server-side HTTP route handlers with no rendered
surface for a client to adjust display or interaction accessibility on.

## Feature Flags

Not applicable: none of these 17 route files reads a feature-flag value;
behavior differences (e.g. `AUTH_DISABLED`, which provider integrations are
configured) are environment/configuration-driven, not flag-driven.

## Analytics

Not applicable: none of these route files emits an analytics event of its
own. `telemetry.ts`'s `GET /analytics` route only serves analytics metrics
that were already captured elsewhere (`storage.telemetry.analytics.load()`);
it does not instrument these routes themselves.

## Privacy

- **Credential storage**: `auth.ts` stores only a password hash
  (`hashPassword`/`verifyPassword`), never a plaintext password; `device.ts`
  stores only `sha256Hex` digests of `device_code` and `user_code`, never
  the plaintext codes, and the raw device-flow token is returned to the
  polling client exactly once, on the single `consumeApproved` call, with
  `Cache-Control: no-store` on that response; `tokens.ts` returns a minted
  API token's raw value exactly once, on creation, also with `no-store`, and
  never again from `GET /tokens`.
- **Timing-attack mitigation as a privacy control**: `auth.ts`'s login path
  runs `verifyPassword` against `DUMMY_PASSWORD_HASH` for an unknown email so
  that response timing does not disclose which emails are registered.
- **Peer credential redaction**: `config.ts`'s `redactPeer` strips a peer's
  raw token from every response (`hasToken` boolean substituted); a peer
  token is write-only through this API.
- **Deliberate exclusion of internal identifiers from a public surface**:
  `reads.ts`'s `buildSnapshot` — the DTO backing `/status/snapshot`, which
  is reachable by anonymous or peer callers — filters out any Problem whose
  `target` is an error target, because that Problem's `name`/`detail` would
  otherwise carry internal GlitchTip project identifiers and raw exception
  titles. This filter is explicitly documented in source as a decision made
  deliberately for disclosure reasons, not an incidental gap, and as
  reversible if the product decision changes.
- **Rate limiting as an abuse/enumeration control**: `auth.ts`'s and
  `device.ts`'s rate limits on `/auth/login`, `/auth/signup`, and the device
  endpoints double as a control against credential-stuffing and account
  enumeration, not only load protection.
- **Scope of what peers can see**: `telemetry.ts` is explicitly excluded from
  the `PEER_TOKEN` credential — a federated peer instance can read this
  instance's health snapshot but not its error/analytics telemetry, keeping
  that data scoped to authenticated dashboard users.

## Logging

Several routes log on failure via `console.error`, and one notably does not:

- `hooks.ts` logs when `ownedBySite`'s roster read fails (the condition that
  drives the 503 fail-closed response), when `runReconcile`'s derivation
  pass fails (fail-soft — the webhook still responds normally), and when
  `upsertDeployments` fails to persist a webhook event (also fail-soft).
- `stream.ts` logs when building a fresh opening-frame snapshot fails (the
  stream still opens, with a null-data opening frame).
- `badge.ts`'s catch-all around snapshot assembly falls back to
  `overall: 'unknown'` with NO logging call at all — a documented contrast
  with the fail-soft-but-logged pattern used elsewhere; a badge render
  failure currently leaves no trace for an operator to notice.

## Platform Notes

- **TypeScript / Node (source)**: the routes are `Hono`/`OpenAPIHono`
  sub-apps composed by factory functions taking `storage`/`config`/
  `scheduler` as explicit parameters (dependency injection over module-level
  singletons), validated with Zod, and returning either a JSON body, an SSE
  `ReadableStream`, or an SVG string.
- **Swift (SwiftUI/AppKit/UIKit hosts)**: a client consuming this contract
  polls `/live`, `/snapshot`, or `/status` on a timer or subscribes to
  `/live/stream` via `URLSession`'s bytes-streaming API to parse SSE frames
  incrementally; the device-authorization flow (`/auth/device` →
  `/auth/device/token` polling) maps naturally onto an `AsyncSequence`-driven
  poll loop with the same `slow_down`/`authorization_pending` back-off
  handling the route itself expects.
- **Kotlin (Jetpack Compose hosts)**: the same SSE stream is consumed via
  OkHttp's `EventSource` (or a manual chunked-response reader) feeding a
  `StateFlow`; the device-flow poll loop is a `Flow` emitting on
  `POLL_INTERVAL_SEC` with the same three-state RFC 8628 error handling.
- **C# / WinUI 3**: a WinUI 3 host is a *client* of this contract, not a
  reimplementation of the server — it would use `HttpClient` for the
  JSON endpoints, `System.Text.Json` for (de)serializing the same DTOs this
  file returns, and a background `Task` looping on `HttpClient.GetAsync`
  against `/live/stream`'s chunked response (or a `System.Net.Http`
  SSE-parsing helper) to feed an `ObservableCollection`/`INotifyPropertyChanged`-
  backed view model, mirroring the subscribe-then-render-opening-frame
  ordering this route enforces server-side. A minted device-flow or API
  token would be persisted client-side via `Windows.Storage`'s credential
  vault, never in a plain settings file. If this route layer itself were
  ever reimplemented on .NET (not just consumed), the Hono
  route-factory/middleware-chain shape maps onto ASP.NET Core minimal APIs
  or controllers for routing, `System.Text.Json` + `FluentValidation` (or
  `DataAnnotations`) in place of Zod, `IHostedService`/`HttpResponse`
  streaming in place of the SSE `ReadableStream`, `HMACSHA1` from
  `System.Security.Cryptography` for the Vercel webhook signature, ASP.NET
  Core's rate-limiting middleware in place of `rateLimit`, and ASP.NET Core
  Identity plus a custom bearer-token `AuthenticationHandler` in place of the
  cookie/session/token middleware chain.
- **Web client**: the dashboard's own frontend is the reference client —
  it opens `EventSource`/`fetch`-based SSE against `/live/stream`, polls
  `/auth/device/token` during device-flow sign-in, and treats every
  `HTTPException` response's `{ error: { message } }` envelope uniformly.

## Design Decisions

- **Decision**: keep the auto-configure matching/creation engine
  (`@agentic-toolkit/deploy-platform/engine`) HTTP-agnostic; the route
  talks to it only through the in-process `statusAdapter`.
  **Rationale**: the engine is reused outside the HTTP layer and stays
  independently testable against a fake `StatusAddApi` without spinning up
  a server.
  **Approved**: pending

- **Decision**: model webhook ownership as a three-state result
  (`owned`/`not-owned`/`unknown`) with `unknown` failing closed to 503,
  rather than a boolean.
  **Rationale**: collapsing "the roster read failed" into "not owned" would
  silently drop a legitimate deploy event during a storage outage; 503
  tells the provider to retry once storage recovers.
  **Approved**: pending

- **Decision**: coalesce concurrent reconcile passes in `hooksRoutes` with a
  single-flight-plus-queued-flag gate rather than letting each webhook
  trigger its own independent reconcile.
  **Rationale**: a burst of webhooks (a multi-service deploy) would
  otherwise fan out into redundant, overlapping board derivations; the
  queued-flag pattern still guarantees every arrival is covered by some
  pass.
  **Approved**: pending

- **Decision**: exclude error-type Problems from `/status/snapshot`'s
  public/anonymous-reachable response.
  **Rationale**: an error Problem's `name`/`detail` carry internal GlitchTip
  project identifiers and raw exception titles that should not be
  disclosed to anonymous or peer callers; this is treated as a decision to
  make deliberately, not an accident of omission.
  **Approved**: pending

- **Decision**: gate `auto-configure.ts` and `board.ts`'s reconcile route
  with `requireAdmin` per-route, while `config.ts`, `users.ts`, and
  `cron.ts` apply it blanket via `app.use('*', ...)`.
  **Rationale**: the former two sub-apps are mounted alongside other,
  non-admin routes at a shared base path; the latter three are entirely
  admin-only sub-apps, so a blanket gate is both correct and simpler there.
  **Approved**: pending

- **Decision**: let `DELETE /tokens/:id` bypass the `requireAdmin`
  middleware in favor of a hand-rolled `isAdmin || isSelf` check.
  **Rationale**: a token must be able to revoke itself as a kill switch
  regardless of its own role; `requireAdmin` alone cannot express "or is the
  target of the call," so the route intentionally does not use it here.
  **Approved**: pending

- **Decision**: leave `/hooks/cloudflare` unimplemented.
  **Rationale**: Cloudflare has no per-deploy webhook to receive, so a route
  would have nothing to verify or dispatch; the existing poll cycle already
  covers Cloudflare deploy status. Documented in source as approved by the
  project owner on 2026-06-26.
  **Approved**: pending

- **Decision**: let `POST /cron/refresh` await its triggered cycle while
  `POST /live/check` triggers its cycle detached (`runNowDetached`).
  **Rationale**: the cron endpoint is called by an external scheduler that
  wants confirmation the cycle ran; the manual "check now" button is
  called from a request a human is actively waiting on and should return
  immediately, with the scheduler's own single-flight covering overlap.
  **Approved**: pending

## Compliance

| Check | Applies via |
|---|---|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | route handlers stay thin, delegating matching/creation to the deploy-platform engine, roster folding to `reconcileBoardLedger`/`deriveBoard`, and persistence guards to `Storage` port methods (`setUserRoleGuarded`, `consumeApproved`, `retireEndpoint`) rather than reimplementing that logic inline. |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | each route file has a corresponding integration test file (e.g. `auth-routes.int.test.ts`, `device-flow.int.test.ts`, `hooks.int.test.ts`, `hooks-gate.test.ts`, `config.int.test.ts`, `stream.int.test.ts`, `activity-route.test.ts`), covering happy paths, error-status mappings, and race scenarios such as the auto-configure rollback test and the concurrent-approve race. |
| [secure-authentication](agenticdevelopercookbook://compliance/security#secure-authentication) | `auth.ts` hashes passwords, runs a dummy-hash comparison for unknown emails to avoid timing disclosure, and normalizes email case before lookup/insert. |
| [token-lifecycle](agenticdevelopercookbook://compliance/security#token-lifecycle) | `device.ts` and `tokens.ts` mint tokens with explicit expiry, hash device/user codes at rest, enforce single-use consumption of an approved device grant, and support revocation (self-or-admin for API tokens). |
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | every mutating route is gated by `requireAdmin`, `requireSessionUser`, or a hand-rolled tier/self check evaluated server-side; none of the 17 files trusts a client-supplied role or tier claim. |
| [rate-limit-handling](agenticdevelopercookbook://compliance/access-patterns#rate-limit-handling) | `auth.ts`'s login/signup routes and `device.ts`'s device-start/token-poll routes apply the `rateLimit` middleware with distinct per-route ceilings. |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | every route throws `HTTPException`, yielding a uniform `{ error: { message } }` envelope with a deliberately chosen status per failure mode (400 validation, 401 credential, 403 authorization, 404 not-found, 409 conflict, 503 unavailable). |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | `activity.ts`'s `GET /activity` implements cursor-based pagination over `(atMs, id)`, including the stall-escape empty-`beforeId` case a page boundary can produce. |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | `board.ts`'s `POST /board/reconcile` is documented and tested as safe to call repeatedly with no state change between calls; `config.ts`'s `runSeed` re-run creates no duplicate rows; `device.ts`'s approve/deny guards make a retried approval a no-op rather than a double-mint. |

## Change History

| Version | Date | Author | Notes |
|---|---|---|---|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
