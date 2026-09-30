<!-- leaf: implement-status-web-hooks/use-activity-history--part-3 · source: status-web-hooks-use-activity-history.md -->

# useActivityHistory — continued (part 3)

**Rules** (cite as `implement-status-web-hooks/use-activity-history--part-3#<slug>`):

- `react-web` MUST — The hook uses standard React primitives (useState, useRef, useEffect, useCallback) and the Fetch API with …

- **uncapped-justification**: An uncapped array is correct because the array's size is bounded by what the reader can actually reach (a page costs a scroll gesture plus a budget reset), sorting large arrays (a few thousand rows) takes milliseconds, and evicting rows would create holes in the middle of the feed that the shed-absorption effect works to prevent.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | — | When false, history is discarded and `loadOlder()` returns without fetching. Required; caller decides whether the age-out filter is active. |
| `live` | ActivityRow[] | — | The current live window's oldest-first rows from `board.activity` (or equivalent live feed). Required; the hook uses this to derive the cursor and detect shed rows. |
| PAGE_SIZE | number | 300 | Hard-coded page size; every request asks for 300 rows. The server clamps to the same value. |
| PAGE_TIMEOUT_MS | number | 20000 | Hard-coded timeout in milliseconds; every fetch aborts if it does not settle within 20 seconds. |
| MAX_AUTOPAGE_FETCHES | number | 5 | Hard-coded auto-fetch budget; `loadOlder()` returns without fetching once this many fetches have started since the last `resetAutoBudget()`. Exported. |

## Platform Notes

- **React/Web**: The hook uses standard React primitives (`useState`, `useRef`, `useEffect`, `useCallback`) and the Fetch API with `AbortController`. A port to another platform MUST provide equivalent state management (mutable refs for stable-identity closures, reactive state for render-triggering values), equivalent async/await with cancellation, and equivalent object/array operations for merge sorting. The comparator `(at, id)` works with any language's string and number types. Error handling relies on try/catch and the response object's `ok` boolean.
- **React Native / TypeScript / Node.js**: Equivalent implementations use the same Fetch API or a polyfill; `AbortController` is available in Node 15+. Replace `useStatusApi()` with the platform-equivalent HTTP client. All logic for merging, shed detection, cursor state, and budget counting is platform-agnostic.
- **Swift / iOS / macOS**: A port would use `@State` properties for `rows`, `loading`, `exhausted`, `error`, `autoBudgetSpent`; plain stored (non-`@State`) properties for cursor, fetch count, flags, abort, and epoch; `URLSession` with `DispatchSourceTimer` or `Task.sleep` for the 20-second timeout; and a publisher-based refresh loop (Combine or async/await) to drive the shed effect when `live` changes. The merge, sort, and guard logic is identical.
- **Kotlin / Android**: A port would use `mutableStateOf` in Compose or `StateFlow`/`LiveData` in traditional Android; `kotlinx.coroutines.Job` and `withTimeoutOrNull` for timeout; `OkHttpClient` for the network request; and a `LaunchedEffect` or `CoroutineScope` to drive the shed effect. Replace `useStatusApi()` with the platform's HTTP client.
- **C# / WinUI 3**: A port would use `ObservableCollection<ActivityRow>` for `rows`, `bool` properties with `INotifyPropertyChanged` for state, `System.Net.Http.HttpClient` with `CancellationTokenSource` for timeout, `Task.Delay` for the 20-second timeout, and `PropertyChanged` events to drive the shed effect. The XAML binding system replaces React's hook dependency tracking. Merge and cursor logic is identical. No localStorage equivalent is needed (in-memory only).

## Design Decisions

**Decision**: History is held in-memory only, with no localStorage persistence.

**Rationale**: The source applies the reasoning in `use-board.ts` unchanged: a durable client store of server-derived rows is what let a fixed problem survive in one browser tab forever. Keeping history in-memory, and dropping it whenever `enabled` goes false, avoids that hazard.

**Approved**: pending

---

**Decision**: History array is uncapped and re-sorted on every merge.

**Rationale**: The array's size is naturally bounded by the reader's reach (a page costs a scroll gesture plus a budget reset) and the 90-day server retention window, typically a few thousand rows at the far end of determined scrolls. Sorting takes milliseconds. A cap would evict rows, creating holes in the middle of the feed that the shed-absorption effect (which exists specifically to prevent holes) would then need to work around, making the cost higher than re-sorting unbounded rows.

**Approved**: pending

---

**Decision**: The shed-absorption effect captures rows only after the first `loadOlder()` call.

**Rationale**: Before paging, there is no history to hole; the live window is the only feed. Once paging starts, a row the window drops afterward falls out of both lists (it is no longer live, and history was paged from where the window's oldest row sat when the scroll began), creating a hole in the middle of the feed. Shed absorption fills this gap cheaply (the row was already transmitted in an earlier frame) without issuing a fetch.

**Approved**: pending

---

**Decision**: Shed rows with `tone: "progress"` are never captured, even if aged out.

**Rationale**: A progress row asserts ongoing work. The server's own freshness contract terminates unconfirmed in-flight phases at 6 hours (far inside the 24h floor), so a progress row aging out is already anomalous. Freezing it as a shed row would create a claim about live work that nothing will ever re-confirm.

**Approved**: pending

---

**Decision**: Failed pages do not roll back the fetch count or advance the cursor.

**Rationale**: The fetch count is a budget that controls spam; it is already spent by the time the request is made. If a page fails with a broken endpoint, rolling back the count would allow retrying that same broken endpoint infinitely via auto-continue. Keeping the cursor unchanged allows the pane to retry the same window on the next scroll without skipping it, but the budget prevents hammering.

**Approved**: pending

---

**Decision**: Timeout is hard-coded at 20 seconds per page, not configurable.

**Rationale**: A request that never settles (dropped connection, proxy holding socket, laptop suspended mid-flight) leaves `loading: true` for the life of the tab, blocking auto-continue and leaving the pane stuck with "loading older activity…". Abandoning the page after 20 seconds surfaces the ordinary error line instead, which the next scroll retries.

**Approved**: pending

---

**Decision**: Merge strategy is incoming-copy-wins, not existing-wins.

**Rationale**: Row ids are stable (`deriveActivity`'s `deployRowId`), so a corrected row arrives under the SAME id with different fields. If existing won, the correction would be silently dropped and the stale copy would remain the only account of that deployment, with no later page able to repair it because cursors only move backward. Incoming is always the more recent read of the same fact; a byte-identical row still leaves `prev` untouched.

**Approved**: pending
