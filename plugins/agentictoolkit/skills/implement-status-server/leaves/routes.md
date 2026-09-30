<!-- leaf: implement-status-server/routes · source: status-server-routes.md -->

**Rules** (cite as `implement-status-server/routes#<slug>`):

- `activity-cursor-pairing` MUST
- `activity-cursor-empty-id-allowed` MUST
- `activity-cursor-range-check` MUST
- `activity-limit-clamping` MUST
- `auth-pre-seam-mounting` MUST
- `auth-signup-normalization` MUST
- `auth-signup-duplicate-detection` MUST
- `auth-login-timing-safety` MUST
- `auth-logout-dual-revocation` MUST
- `auth-me-never-unauthenticated` MUST
- `auth-rate-limits` MUST
- `auth-oauth-mounting` MUST
- `auto-configure-admin-gate` MUST
- `auto-configure-opt-out-respected` MUST
- `auto-configure-ignore-persistence` MUST
- `auto-configure-create-target-validation` MUST
- `auto-configure-lite-adapter` MUST
- `auto-configure-site-purge-on-delete` MUST
- `auto-configure-skip-dedup` MUST
- `auto-configure-reconcile-sweep` MUST
- `badge-overall-remapping` MUST
- `badge-error-fallback` MUST
- `badge-caching` MUST
- `badge-svg-shape` MUST
- `board-read-always-fresh` MUST
- `board-reconcile-admin-gate` MUST
- `board-reconcile-skip-on-empty-roster` MUST
- `board-reconcile-idempotent` MUST
- `board-reconcile-can-alert` MUST

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

