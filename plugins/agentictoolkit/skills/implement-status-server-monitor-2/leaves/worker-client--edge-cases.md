<!-- leaf: implement-status-server-monitor-2/worker-client--edge-cases · source: status-server-monitor-worker-client.md -->

# Status Server Monitor Worker Client

**Rules** (cite as `implement-status-server-monitor-2/worker-client--edge-cases#<slug>`):

- `null-and-empty-input` MUST — a not-ok CycleReply with no error field MUST fall back to the literal message monitor cycle failed …
- `boundary-values` MUST — opts.cycleTimeoutMs of 0, a negative number, or NaN is not validated or clamped anywhere in this file; it is handed …
- `concurrent-access` MUST — nothing in this file serializes runCycle calls — two or more overlapping calls against the same worker are each …
- `error-states` MUST — a CycleReply with ok: false rejects only its own matching entry (reply-not-ok-rejects-with-message) — MUST. A "error" …

## Edge Cases

- **Null and empty input**: a not-`ok` `CycleReply` with no `error` field MUST fall back to the literal message `monitor cycle failed` (reply-not-ok-rejects-with-message) — MUST. A `workerData.db`/`workerData.config` of `null` or `undefined` is passed through unchanged into the spawned worker; validating it is entirely `worker.ts`'s job (its own `if (!conn?.url) throw ...` / `if (!config) throw ...`), not this file's — MUST.
- **Boundary values**: `opts.cycleTimeoutMs` of `0`, a negative number, or `NaN` is not validated or clamped anywhere in this file; it is handed directly to `setTimeout`, whose own runtime semantics govern the resulting delay — MUST NOT be read as this file enforcing any minimum or maximum. `seq` increments once per `runCycle` call for the lifetime of the client instance, never reset by a respawn, with no wraparound guard against `Number.MAX_SAFE_INTEGER` — undocumented if ever reached, though unreachable at any real monitor cadence.
- **Concurrent access**: nothing in this file serializes `runCycle` calls — two or more overlapping calls against the same worker are each dispatched immediately and tracked independently by their own `seq` (no-single-flight-guard) — MUST. A direct consequence: when one call's timeout terminates the shared worker, every OTHER call still pending against that same worker is rejected too, via the resulting `"exit"` event, not just the call that actually timed out (terminated-worker-exit-cascades-to-sibling-pending) — MUST.
- **Error states**: a `CycleReply` with `ok: false` rejects only its own matching entry (reply-not-ok-rejects-with-message) — MUST. A `"error"` or `"exit"` event on the worker rejects EVERY currently pending entry, whether or not each one individually timed out (worker-error-rejects-all-pending, worker-exit-rejects-all-pending) — MUST. A reply for a `seq` no longer present in `pending` is silently ignored, with no throw and no log (unmatched-reply-ignored) — MUST.
- **Offline / disconnected state**: this component has no network dependency of its own — it exchanges only in-process `worker_threads` messages, never an HTTP request. Its equivalent of "connectivity loss" is losing the underlying worker thread (a crash, a forced termination on timeout, or an unexpected exit), which is fully specified under Error states above; there is no additional degraded mode beyond what those requirements already define.
