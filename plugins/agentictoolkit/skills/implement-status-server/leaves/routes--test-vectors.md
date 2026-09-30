<!-- leaf: implement-status-server/routes--test-vectors · source: status-server-routes.md -->

# Status Server Routes

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
