<!-- leaf: implement-status-web-hooks/use-refresh-all--part-2 · source: status-web-hooks-use-refresh-all.md -->

# useRefreshAll — continued (part 2)

## Design Decisions

**Decision**: Refresh every supporting query on one shared tick instead of giving each query its own `refetchInterval`.
**Rationale**: The doc comment says the goal is that "the dashboard never shows a mix of fresh + stale datasets". `BoardShell` repeats it: "no staggered, mismatched state." The refetches start together but still finish independently.
**Approved**: pending

**Decision**: Exclude the `"live"` query from the shared tick.
**Rationale**: The live query drives itself through `use-live-snapshot`'s own `refetchInterval`, which stands down while the SSE stream is connected. Refetching it here "would double the provider fan-out to two polls per minute per client."
**Approved**: pending

**Decision**: Skip disabled queries.
**Rationale**: An observer with `enabled: false` "opted OUT of fetching — refetching it here would undo that gate every 60s." Because `isDisabled()` is false while any observer is enabled, `BoardShell` relies on the config-status gate being the role gate only.
**Approved**: pending

**Decision**: Select queries with a predicate over the whole cache instead of a list of keys.
**Rationale**: New datasets join the shared refresh automatically with no edit to this hook. The trade-off is that an unobserved cached query that has fetched before is also refetched until it is garbage-collected (react-query v5 default).
**Approved**: pending

**Decision**: Make `refreshAll` fire-and-forget.
**Rationale**: Results and errors belong to each query's observers. The aggregate promise carries no useful signal, and discarding it with `void` satisfies the no-floating-promise lint.
**Approved**: pending
