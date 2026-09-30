<!-- leaf: implement-status-web-hooks/use-refresh-all--edge-cases · source: status-web-hooks-use-refresh-all.md -->

# useRefreshAll

**Rules** (cite as `implement-status-web-hooks/use-refresh-all--edge-cases#<slug>`):

- `empty-cache` MUST — With no queries in the QueryClient, refreshAll MUST still call refetchQueries. That call refetches nothing and resolves.
- `only-the-live-query-cached` MUST — refreshAll MUST refetch nothing. The live query keeps its own cadence, set by use-live-snapshot (refetchInterval: …
- `empty-query-key` MUST — For a query with key [], queryKey[0] is undefined, so that query MUST NOT be excluded as live. It is refetched if it is …
- `non-string-first-key-element` MUST — The comparison is strict (!==), so a first element that is not the string "live" (for example a number or an object) …
- `intervalms-of-0-negative-or-nan` MUST — Passed to setInterval unchanged. Browsers treat these as a zero delay, clamped to their minimum timer interval (about 4 …
- `very-large-intervalms` MUST — A value above 2,147,483,647 ms overflows the browser's 32-bit timer delay and fires almost immediately. The hook does …
- `tick-during-an-in-flight-fetch` MUST — react-query cancels the running fetch and restarts it (cancelRefetch defaults to true for refetchQueries in v5). The …
- `refetch-failure-unreachable-server-offline` MUST — Each failing query records its error in its own cache state, and the hook MUST NOT surface, retry or log it. Retries …
- `background-tab` MUST — The timer keeps running, subject to browser throttling. The hook MUST NOT skip or delay ticks itself.
- `unmount-mid-refetch` MUST — Refetches already started keep running and still update the cache. Unmount only stops future ticks (MUST, as …
- `queryclient-swapped` MUST — A new client changes refreshAll's identity, so the effect restarts the timer against the new client. The old client …
- `missing-provider` MUST — Rendering outside a QueryClientProvider MUST throw from useQueryClient() during render.

## Edge Cases

- **Empty cache**: With no queries in the `QueryClient`, `refreshAll` MUST still call `refetchQueries`. That call refetches nothing and resolves.
- **Only the live query cached**: `refreshAll` MUST refetch nothing. The live query keeps its own cadence, set by `use-live-snapshot` (`refetchInterval: streamConnected ? false : POLL_INTERVAL_MS`).
- **Empty query key**: For a query with key `[]`, `queryKey[0]` is `undefined`, so that query MUST NOT be excluded as live. It is refetched if it is not disabled.
- **Non-string first key element**: The comparison is strict (`!==`), so a first element that is not the string `"live"` (for example a number or an object) MUST NOT be excluded.
- **`intervalMs` of 0, negative or `NaN`**: Passed to `setInterval` unchanged. Browsers treat these as a zero delay, clamped to their minimum timer interval (about 4 ms once nested), so the hook MUST then fire refreshes continuously. The only caller passes `60_000`. The value is a caller precondition set by the `number` signature and that call site.
- **Very large `intervalMs`**: A value above 2,147,483,647 ms overflows the browser's 32-bit timer delay and fires almost immediately. The hook does not guard against this, and MUST pass the value through unchanged.
- **Tick during an in-flight fetch**: react-query cancels the running fetch and restarts it (`cancelRefetch` defaults to `true` for `refetchQueries` in v5). The hook MUST NOT add its own deduplication.
- **Refetch failure / unreachable server / offline**: Each failing query records its error in its own cache state, and the hook MUST NOT surface, retry or log it. Retries follow the host `QueryClient` defaults. While offline, react-query's network mode may pause fetches. That behavior belongs to react-query.
- **Background tab**: The timer keeps running, subject to browser throttling. The hook MUST NOT skip or delay ticks itself.
- **Unmount mid-refetch**: Refetches already started keep running and still update the cache. Unmount only stops future ticks (MUST, as implemented).
- **Cancellation and timeout**: The hook has no cancellation or timeout of its own. Timeouts, if any, belong to each query function and its transport.
- **`QueryClient` swapped**: A new client changes `refreshAll`'s identity, so the effect restarts the timer against the new client. The old client gets no more ticks from this mount (MUST).
- **Missing provider**: Rendering outside a `QueryClientProvider` MUST throw from `useQueryClient()` during render.
