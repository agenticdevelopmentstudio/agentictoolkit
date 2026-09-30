<!-- leaf: implement-status-web-hooks/use-activity-history--edge-cases · source: status-web-hooks-use-activity-history.md -->

# useActivityHistory

**Rules** (cite as `implement-status-web-hooks/use-activity-history--edge-cases#<slug>`):

- `empty-live-window` MUST
- `live-window-becomes-empty` MUST
- `fetch-timeout-20-seconds` MUST

## Edge Cases

- **empty-live-window**: When the live window is empty on the first call to `loadOlder()`, the hook MUST request with no cursor, causing the server to serve the newest page it has. No error is raised; this case is explicitly supported for quiet fleets whose 24h window holds nothing.
- **live-window-aged-past-history**: Before the reader has paged, rows the live window sheds are let go (`prevLive` still advances); the first page then starts from wherever the window's oldest row has moved to, so no gap forms.
- **live-window-becomes-empty**: If the live window becomes empty in a render (indicating stale data or API blip), the shed effect MUST NOT trigger; the previous window is retained. The next render with a non-empty window resumes shed absorption.
- **fetch-timeout-20-seconds**: Any fetch that does not settle within 20 seconds (whether dropped connection, proxy holding socket, laptop suspended, or unresponsive server) MUST be aborted and treated as an error. The timeout is not retried automatically; the next `loadOlder()` call retries the same window.
- **row-id-collision-merge**: If the same `id` appears in both the previous `rows` and an incoming page, the incoming copy is kept and the previous is discarded. If incoming is byte-identical to previous, the array is not mutated.
- **concurrent-enabled-false-and-fetch**: If `enabled` goes false while a fetch is in flight, the request is aborted and the epoch increments; if the component unmounts, the request is aborted and `mounted` goes false. Either way a response that still lands is dropped by the epoch/mount check before `setRows`, and a request started after a re-enable keeps its own latch because the stale `finally` block skips clearing `inFlight`/`loading`.
- **shed-row-no-longer-live**: A row is shed only if it no longer appears in the live window by `id` AND it sorts before the window's oldest row. A row that leaves without sorting behind what the window still holds (for example a superseded `deploying` deployment whose row stops being derived, or an endpoint disabled or renamed) is not captured, and a `progress` row is never captured, avoiding freezing a still-changing row.
- **no-automatic-retry-on-error**: Errors are not automatically retried; they are reported in `error: true` and the pane is responsible for calling `loadOlder()` again in response to user scroll.
- **history-reset-on-reenable**: History is discarded the moment `enabled` goes false (the age-out filter comes back on) and is NOT restored when `enabled` returns to true; it is invisible under any TTL, and keeping it would make the memory cost of a scroll permanent for the session.
- **budget-independent-of-success**: The auto-fetch budget is incremented at the start of each call, not after success. A page that fails still consumes one budget slot; this prevents a broken endpoint from being retried infinitely by the auto-continue effect.
- **null-oldest-handling**: When `live[0]` is undefined, `oldest` is `null`: the shed effect returns early without updating `prevLive`, and `loadOlder()` sends no cursor if `cursorRef` is also null. No crash occurs.
