<!-- leaf: implement-status-server/libsql--edge-cases · source: status-server-libsql.md -->

# Status Server Libsql

## Edge Cases

- **Null and empty input**: an empty `conn.url` is rejected explicitly by
  connection-url-required, the one input validation these two files
  perform; every other "missing" value in the schema (a nullable column
  with no default — `providerProjectId`, `error`, `resolvedReason`,
  `deployProjectId`, `token`) is a first-class, documented `null`, not an
  unhandled gap.
- **Boundary values**: `checkpointWal`'s `frames` defaults to `0` when the
  checkpoint result row or its `checkpointed` field is absent
  (checkpoint-result-shape) — the coalesce (`?? 0`) is a boundary case the
  source handles explicitly, not an unguarded read. `metricsHourly.hour`
  and `analyticsMetrics.capturedAt` are unix-second timestamps truncated to
  their aggregation boundary by callers external to this file (`hour`
  itself carries no truncation logic in `schema.ts`).
- **Concurrent access**: the entire concurrency-tuning half of
  `client.ts` (tune-wal-mode, tune-busy-timeout, tune-synchronous-normal)
  exists because the API server and the monitor worker hold independent
  connections to the same embedded file. `uniq_open_issue_per_target` and
  `uniq_metrics_service_hour` are the schema's own concurrency guards —
  a losing concurrent insert is rejected by the database itself, not
  silently merged. `checkpointWal`'s fail-soft `busy` result is the
  documented outcome when a checkpoint races a live reader.
- **Error states**: `openLibsql` throws synchronously for the one input it
  validates (an empty `url`); every unique-index and foreign-key violation
  in the schema (issue-uniqueness-open, metrics-hourly-uniqueness,
  peer-uniqueness, user-uniqueness, session-token-hash-only,
  api-token-hash-only, device-auth-hash-only-except-raw) surfaces as a
  rejected promise from the underlying libSQL driver — neither file
  wraps or swallows a driver rejection anywhere.
- **Offline / disconnected state**: a remote libsql/Turso connection going
  unreachable is not handled by either file — `isEmbeddedFile` routes all
  tuning and checkpointing around remote connections specifically because,
  per the source comment, "remote libsql/Turso manages its own journaling
  and durability" and "its own storage." Reconnection, retry, and
  backoff for a remote connection are the responsibility of the `@libsql/client`
  driver `drizzle()` wraps, external to these two files.
