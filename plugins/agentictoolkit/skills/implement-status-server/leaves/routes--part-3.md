<!-- leaf: implement-status-server/routes--part-3 · source: status-server-routes.md -->

# Status Server Routes — continued (part 3)

**Rules** (cite as `implement-status-server/routes--part-3#<slug>`):

- `hooks-pre-seam-mounting` MUST
- `hooks-ownership-three-way` MUST
- `hooks-fail-closed-on-unknown-ownership` MUST
- `hooks-signature-before-parse` MUST
- `hooks-secret-unconfigured` MUST
- `hooks-unparseable-avoids-retry-storm` MUST
- `hooks-unmapped-event-ignored` MUST
- `hooks-railway-shared-secret` MUST
- `hooks-persist-fail-soft` MUST
- `hooks-derivation-fail-soft` MUST
- `hooks-reconcile-single-flight-coalescing` MUST
- `hooks-live-buffer-and-broadcast` MUST
- `read-body-canonical-helper` MUST
- `reads-live-owner-bound-first` MUST
- `reads-live-buffer-overlay` MUST
- `reads-problems-single-producer` MUST
- `reads-snapshot-error-redaction` MUST
- `reads-deploy-cache-atomicity` MUST
- `reads-deploy-projects-shared-cache` MUST
- `reads-history-slug-required` MUST
- `reads-history-hours-clamp` MUST
- `reads-uptime-days-clamp` MUST
- `reads-response-history-clamps` MUST
- `reads-endpoint-wiring-paused-claims` MUST
- `reads-correlate-ignore-vs-wire-granularity` MUST
- `stream-opening-frame` MUST
- `stream-subscribe-before-send` MUST
- `stream-heartbeat` MUST
- `stream-lifetime-cap` MUST
- `stream-cleanup-idempotent` MUST
- `stream-check-requires-scheduler` MUST
- `stream-check-debounce` MUST
- `stream-check-detached` MUST
- `stream-check-test-reset-hook` MUST

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

