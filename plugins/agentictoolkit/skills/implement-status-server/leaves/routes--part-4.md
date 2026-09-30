<!-- leaf: implement-status-server/routes--part-4 · source: status-server-routes.md -->

# Status Server Routes — continued (part 4)

**Rules** (cite as `implement-status-server/routes--part-4#<slug>`):

- `telemetry-injectable-fetchers` MUST
- `telemetry-last-good-fallback` MUST
- `telemetry-single-flight-cache` MUST
- `telemetry-no-store` MUST
- `telemetry-db-backed-endpoints` MUST
- `telemetry-analytics-latest-reduction` MUST
- `telemetry-peer-token-excluded` MUST
- `tokens-mint-requires-session-admin` MUST
- `tokens-mint-raw-once` MUST
- `tokens-list-no-store` MUST
- `tokens-delete-self-or-admin` MUST
- `tokens-delete-not-found` MUST
- `users-blanket-admin-gate` MUST
- `users-role-body-validation` MUST
- `users-last-admin-guard-atomic` MUST
- `users-delete-last-admin-guard-atomic` MUST

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

