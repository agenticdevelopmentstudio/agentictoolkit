<!-- leaf: implement-status-web-hooks/use-portfolio-indicator--edge-cases · source: status-web-hooks-use-portfolio-indicator.md -->

# usePortfolioIndicator

**Rules** (cite as `implement-status-web-hooks/use-portfolio-indicator--edge-cases#<slug>`):

- `no-data-yet` MUST — Before either feed has answered (snapshot: null, board: null), pillKey MUST be "unknown" and count MUST be 0; the …
- `board-present-snapshot-not-yet-read` MUST — With a non-null board and snapshot: null, the hook MUST return the board's mapped verdict, since a null snapshot is …
- `zero-endpoint-monitor` MUST — A snapshot with an empty services list sets blind, so pillKey MUST be "unknown" even if the board reports "operational".
- `zero-problems` MUST — A non-null board with an empty problems array MUST yield count === 0; the colour still comes from board.indicator, not …
- `unknown-with-a-count` MUST — When the live feed is offline, blind or stale but the board is current, the hook MUST return "unknown" together with …
- `stale-window-boundary` MUST — A lag exactly equal to the stale window MUST be fresh; one millisecond more MUST be stale (portfolio-007, …
- `missing-probe-interval` MUST — A snapshot from an older backend with no probeIntervalMs MUST be judged against the 300 000 ms floor.
- `malformed-timestamps` MUST — An unparseable lastCycleAt or generatedAt MUST be treated as fresh, so it never forces "unknown" on its own; this is …
- `client-clock-skew-or-sleeping-tab` MUST — The snapshot verdict MUST be unaffected, since it compares two server timestamps only. The board staleness verdict …
- `network-failure-or-unreachable-server` MUST — The hook MUST NOT handle transport errors itself; a failed board read surfaces as board: null from useBoard and a dead …
- `concurrent-calls` MUST — Multiple components MAY call the hook at once; each call derives independently from the same shared React Query caches …

## Edge Cases

- **No data yet**: Before either feed has answered (`snapshot: null`, `board: null`), `pillKey` MUST be `"unknown"` and `count` MUST be `0`; the source comment explains that without this the pill "would render a false green 'operational' off nothing before the first read lands".
- **Board present, snapshot not yet read**: With a non-null board and `snapshot: null`, the hook MUST return the board's mapped verdict, since a null snapshot is neither offline, blind nor stale.
- **Zero-endpoint monitor**: A snapshot with an empty `services` list sets `blind`, so `pillKey` MUST be `"unknown"` even if the board reports `"operational"`.
- **Zero problems**: A non-null board with an empty `problems` array MUST yield `count === 0`; the colour still comes from `board.indicator`, not from the count.
- **Unknown with a count**: When the live feed is offline, blind or stale but the board is current, the hook MUST return `"unknown"` together with the board's non-zero problem count; callers that print a number next to an unknown glyph see the board's count.
- **Stale window boundary**: A lag exactly equal to the stale window MUST be fresh; one millisecond more MUST be stale (portfolio-007, portfolio-008).
- **Missing probe interval**: A snapshot from an older backend with no `probeIntervalMs` MUST be judged against the 300 000 ms floor.
- **Malformed timestamps**: An unparseable `lastCycleAt` or `generatedAt` MUST be treated as fresh, so it never forces `"unknown"` on its own; this is the deliberate behaviour of `snapshotFreshness`.
- **Client clock skew or sleeping tab**: The snapshot verdict MUST be unaffected, since it compares two server timestamps only. The board staleness verdict applied inside `useBoard` is that hook's contract, not this one's.
- **Unmapped indicator**: A `board.indicator` outside `"operational" | "degraded" | "outage"` is excluded by the `Indicator` type; the hook does no runtime check and would return `undefined` as `pillKey`. The board shape is owned by the server and mirrored in `lib/board-types.ts`.
- **Network failure or unreachable server**: The hook MUST NOT handle transport errors itself; a failed board read surfaces as `board: null` from `useBoard` and a dead live feed surfaces as `offline: true` from `useLiveSnapshot`, and both MUST yield `"unknown"`.
- **Timeouts, cancellation and retries**: The hook has none; any timeout, retry or cancellation belongs to `useBoard` and `useLiveSnapshot`.
- **Concurrent calls**: Multiple components MAY call the hook at once; each call derives independently from the same shared React Query caches and live store, so callers under one `QueryClient` MUST see the same verdict in the same render pass. JavaScript is single-threaded, so there is no interleaving within the hook.
