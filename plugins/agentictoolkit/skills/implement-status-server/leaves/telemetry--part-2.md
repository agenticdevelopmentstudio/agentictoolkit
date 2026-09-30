<!-- leaf: implement-status-server/telemetry--part-2 · source: status-server-telemetry.md -->

# Status Server Telemetry — continued (part 2)

**Rules** (cite as `implement-status-server/telemetry--part-2#<slug>`):

- `rationale` MUST — Appending stores (e.g., trend tables) ignore complete because new records never conflict. Reconciling stores (e.g., …
- `rationale-2` MUST — A provider outage (GlitchTip down, network unreachable) MUST NOT prevent analytics collection or platform-health …

## Design Decisions

**Decision**: A failed provider poll (ok:false) is never persisted, and the Store is never called.

**Rationale**: This prevents transient provider outages from overwriting known-good data with an empty set. Downstream logic (error rules, trend tracking) can rely on `last_seen` only advancing when new data actually arrives. A blind spot (provider unreachable) is tracked separately via platform-health observations, not by sweeping historical records.

**Approved**: pending

---

**Decision**: The `complete` flag is threaded through `collect()` uninterpreted and passed to `store.save()` for the store to decide how to use it.

**Rationale**: Appending stores (e.g., trend tables) ignore `complete` because new records never conflict. Reconciling stores (e.g., current-issue tables) MUST respect `complete: false` to avoid false resolution of issues not in the current page. By making the distinction explicit at the interface level, we prevent a paginating fetcher from accidentally wiping unseen items.

**Approved**: pending

---

**Decision**: `collectTelemetry()` polls errors and analytics concurrently via `Promise.all()`, not serially.

**Rationale**: Polling both providers serially meant the cycle's duration equaled the sum of both timeouts, which, stacked on the deploy polls, helped blow the scheduler's cycle budget and trigger container restarts. Concurrent polling reduces the critical path to the slower provider's timeout alone.

**Approved**: pending

---

**Decision**: Unconfigured providers (missing credentials) are skipped, and the GlitchTip platform-health observation records `configured: false, reachable: true`.

**Rationale**: Unconfigured is not the same as unreachable — nothing was asked, so nothing failed. Recording `configured: false` tells downstream that the feature is off (e.g., GlitchTip integration disabled), allowing the status dashboard to distinguish between "we're not listening to this provider" and "we're listening but it's down". An absent observation row after removing env vars would leave a stale `configured: true` behind.

**Approved**: pending

---

**Decision**: Provider collection failures are caught individually and do not abort the cycle; each logs to `console.error()` and the `collectTelemetry` function continues.

**Rationale**: A provider outage (GlitchTip down, network unreachable) MUST NOT prevent analytics collection or platform-health recording. The fail-soft pattern ensures one provider's problems are isolated, and the GlitchTip platform-health row signals an errors-provider outage to downstream rules; an analytics failure is visible only in the logs.

**Approved**: pending
