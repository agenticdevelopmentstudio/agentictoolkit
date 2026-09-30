<!-- leaf: implement-status-server-monitor-1/live-buffer--part-2 · source: status-server-monitor-live-buffer.md -->

# Status Server Monitor Live Buffer — continued (part 2)

## Design Decisions

- **Decision**: bound the buffer by a fixed entry count (200, via `splice`-based front-eviction of the oldest entries) rather than by a time-based expiry.
  **Rationale**: matches the module's own doc comment directly — the buffer only ever "shortens latency," it is never the source of truth (the periodic poll is), so a fixed count is a cheap, deterministic memory bound that needs no timer, no scheduled sweep, and no clock dependency of its own beyond the `Date.now()` already read on push. The risk of evicting an entry a slow reader has not yet consumed is real but accepted for the same reason: the poll this file defers to recovers anything the buffer fails to deliver.
  **Approved**: pending
- **Decision**: keep the buffer as bare module-scope state (one shared array) instead of a factory-created, explicitly-constructed instance.
  **Rationale**: the consuming server runs `hooks.ts` and `reads.ts` inside a single Node process per instance, so a module-scope singleton is the simplest shape for that topology; this also explains why `clearDeployEvents` exists purely as a test seam ("module state persists across vitest cases," per its own doc comment) rather than a general-purpose reset API a production caller would ever need.
  **Approved**: pending
- **Decision**: accept per-instance, best-effort delivery on multi-instance serverless deployments instead of centralizing the buffer in a shared store (e.g. Redis or the database).
  **Rationale**: stated directly in the module's own top-of-file comment — exact on a long-running server, best-effort on Vercel serverless because each warm instance owns a private buffer and an event may land on an instance a given read never reaches. Accepted because the 60-second poll (external to this file) independently re-reads provider truth, so the buffer can only ever shorten user-visible latency, never be relied on to carry information the poll cannot recover on its own.
  **Approved**: pending
- **Decision**: leave `deployEventsSince`'s `sinceMs` parameter general-purpose even though its one production caller (`reads.ts`'s `deploymentDtos`) always passes `0`.
  **Rationale**: not stated in a comment; observed directly at the call site. Documented here rather than treated as a gap in this file, because a constant argument at the one call site is a fact about that caller's current design, not an unmet contract in `deployEventsSince` itself, which remains free to be called with any `sinceMs` a future caller needs.
  **Approved**: pending
- **Decision**: keep both id-based deduplication (the "newest info wins an id-merge downstream" the module's own doc comment on `deployEventsSince` references) and ownership filtering out of this file, leaving `deployEventsSince` to return every buffered entry unfiltered and unmerged.
  **Rationale**: `reads.ts`'s `deploymentDtos` is the one place that folds buffer entries into a `Map` keyed by `id` and applies its `keep` ownership predicate (confirmed by test vector 006). Keeping this file's contract to exactly "store, evict, and filter by time" keeps it a single, narrow concern per `separation-of-concerns`, leaving the id-merge and ownership policy to change independently in `reads.ts` without touching this file.
  **Approved**: pending
