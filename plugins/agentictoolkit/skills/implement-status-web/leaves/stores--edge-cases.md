<!-- leaf: implement-status-web/stores--edge-cases · source: status-web-stores.md -->

# Status Web Stores

**Rules** (cite as `implement-status-web/stores--edge-cases#<slug>`):

- `null-or-empty-stored-value` MUST — getItem returns null (never saved) or "" → load returns null (MUST, parse-null-empty, load-missing-key).
- `corrupt-stored-value` MUST — The key holds malformed JSON, null, a scalar, or an object missing generatedAt, errors or analytics → load returns null …
- `boundary-empty-arrays-and-empty-timestamp` MUST — { generatedAt: "", errors: [], analytics: [] } passes the gate and is returned as is; this is the same value …
- `malformed-array-elements` MUST — errors or analytics contain values that are not DTOs → returned unchanged; consumers receive them as typed DTOs (MUST, …
- `storage-unavailable` MUST — localStorage access throws (storage blocked, sandboxed iframe) → load returns null and save is a no-op, both silently …
- `quota-exceeded` MUST — setItem throws because the serialized snapshot does not fit → the write is dropped silently; the previous stored value, …
- `non-browser-runtime` MUST — window undefined during server render → load returns null, save is a no-op (MUST, load-no-window, save-no-window).
- `concurrent-access` MUST — Within one page, JavaScript is single-threaded and both calls are synchronous, so no interleaving is possible. Across …
- `offline-or-disconnected` MUST — The adapter does no network I/O; offline is the case it exists for — load still returns the last saved snapshot (MUST, …

## Edge Cases

- **Null or empty stored value**: `getItem` returns `null` (never saved) or `""` → `load` returns `null` (MUST, parse-null-empty, load-missing-key).
- **Corrupt stored value**: The key holds malformed JSON, `null`, a scalar, or an object missing `generatedAt`, `errors` or `analytics` → `load` returns `null` and leaves the value in place (MUST, load-no-cleanup).
- **Boundary: empty arrays and empty timestamp**: `{ generatedAt: "", errors: [], analytics: [] }` passes the gate and is returned as is; this is the same value `emptySnapshot()` produces (MUST, stores-011).
- **Malformed array elements**: `errors` or `analytics` contain values that are not DTOs → returned unchanged; consumers receive them as typed DTOs (MUST, parse-shallow). The stored value normally comes only from this adapter's own `save` of a typed snapshot; see Design Decisions.
- **Schema change**: A future incompatible `TelemetrySnapshot` shape that still has a string `generatedAt` and two arrays passes the gate; the versioned key name `adh-telemetry-v1` is the only migration lever (fact).
- **Storage unavailable**: `localStorage` access throws (storage blocked, sandboxed iframe) → `load` returns `null` and `save` is a no-op, both silently (MUST, load-storage-throws, save-best-effort).
- **Quota exceeded**: `setItem` throws because the serialized snapshot does not fit → the write is dropped silently; the previous stored value, if any, remains (MUST, save-best-effort).
- **Non-browser runtime**: `window` undefined during server render → `load` returns `null`, `save` is a no-op (MUST, load-no-window, save-no-window).
- **Concurrent access**: Within one page, JavaScript is single-threaded and both calls are synchronous, so no interleaving is possible. Across tabs of the same origin, the last `save` wins with no coordination and no `storage` event handling (MUST, cross-tab-last-write).
- **Offline or disconnected**: The adapter does no network I/O; offline is the case it exists for — `load` still returns the last saved snapshot (MUST, only-side-effect, durability-reload).
- **Cancellation and timeouts**: Not applicable — both operations are synchronous and bounded by one storage call; there is nothing to cancel and no timeout.
