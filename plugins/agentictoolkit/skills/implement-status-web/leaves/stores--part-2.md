<!-- leaf: implement-status-web/stores--part-2 · source: status-web-stores.md -->

# Status Web Stores — continued (part 2)

## Design Decisions

**Decision**: The read path is a shallow shape gate (`generatedAt` string, `errors` and `analytics` arrays) and does not validate array elements.
**Rationale**: The stored value is written only by this adapter's own `save` of a typed `TelemetrySnapshot`, so the gate guards against a corrupt, truncated or foreign value rather than re-validating trusted DTOs; the source comment calls it a "defensive, shape-gated parse — anything off → null". The versioned key name is the migration lever for an incompatible shape change.
**Approved**: pending

**Decision**: Both operations swallow every storage exception silently — `load` returns `null`, `save` does nothing.
**Rationale**: The cache is an optimization for instant paint and last-known view; the source comment states "best-effort — the in-memory query result is the live truth". A cache failure degrades to the no-cache path the consumer already handles (`emptySnapshot()` until the live query lands).
**Approved**: pending

**Decision**: `parseSnapshot` is split out as a pure exported function.
**Rationale**: The source comment says the split makes the parse "unit-testable without a browser; the adapter only adds the window/localStorage I/O". `local-cache.test.ts` tests only `parseSnapshot`.
**Approved**: pending

**Decision**: The port is synchronous.
**Rationale**: `localStorage` is synchronous, and the consumer reads the cache in a mount effect to paint before any network result; an async port would add a frame of empty state. Ports whose backing store is asynchronous change the signature (see Platform Notes, WinUI 3 and Compose).
**Approved**: pending

**Decision**: A stored value that fails the parse is left in place, and `save` does not project extra keys.
**Rationale**: The source has no cleanup or projection on the write path; the next successful `save` overwrites the key in full, so a stale or corrupt value costs one cold paint at most.
**Approved**: pending
