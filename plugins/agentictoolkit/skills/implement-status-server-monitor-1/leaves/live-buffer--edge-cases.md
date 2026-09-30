<!-- leaf: implement-status-server-monitor-1/live-buffer--edge-cases · source: status-server-monitor-live-buffer.md -->

# Status Server Monitor Live Buffer

**Rules** (cite as `implement-status-server-monitor-1/live-buffer--edge-cases#<slug>`):

- `null-and-empty-input` MUST — deployEventsSince(sinceMs) called against an empty buffer MUST return [], regardless of sinceMs's value. …
- `boundary-values` MUST — pushing exactly CAP (200) entries MUST leave the buffer at length 200 with no eviction; pushing one more (the 201st) …
- `concurrent-access` MUST — within a single process, pushDeployEvent, deployEventsSince, and clearDeployEvents cannot interleave their reads and …

## Edge Cases

- **Null and empty input**: `deployEventsSince(sinceMs)` called against an empty buffer MUST return `[]`, regardless of `sinceMs`'s value. `deployEventsSince(0)` against a non-empty buffer MUST return every entry, since every `receivedAt` produced by `Date.now()` is a positive number and therefore `>= 0` — MUST. `clearDeployEvents()` called against an already-empty buffer MUST be a no-op that raises no error (see `clear-is-idempotent`) — MUST.
- **Boundary values**: pushing exactly `CAP` (200) entries MUST leave the buffer at length 200 with no eviction; pushing one more (the 201st) MUST evict exactly the single oldest entry, per the `buffer.length - CAP` argument to `splice` evaluating to exactly 1 at that point — MUST. `deployEventsSince` at the exact `receivedAt` value of an entry MUST include that entry (the `>=` comparison), while a `sinceMs` one millisecond later MUST exclude it — MUST.
- **Concurrent access**: within a single process, `pushDeployEvent`, `deployEventsSince`, and `clearDeployEvents` cannot interleave their reads and writes of the shared `buffer` array, because none of the three performs an `await` or any other yield point between reading and mutating it — this is a fact of JavaScript's single-threaded execution model, not a lock this file implements (see `synchronous-single-threaded-execution`) — MUST. Across process instances (the multi-instance serverless case the module's own comment names), there is no synchronization of any kind: each instance's `buffer` is entirely private, and the accepted mitigation is the external provider poll, not any coordination this file performs — MUST (see `per-instance-scope-on-multi-instance-deployment`).
- **Error states**: Not applicable — this file performs no network call, file I/O, or database access of any kind; it has no dependency that can fail or return an error for it to handle.
- **Offline or disconnected state**: Not applicable — this file has no network connectivity of its own to lose. It only decides what an already-in-memory buffer holds and returns; the network I/O that produces the events it buffers (the webhook HTTP request handled by `hooks.ts`) and the network I/O that the poll it defers to performs are both external to this file.
