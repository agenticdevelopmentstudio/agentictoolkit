<!-- leaf: implement-status-server/routes--edge-cases · source: status-server-routes.md -->

# Status Server Routes

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
