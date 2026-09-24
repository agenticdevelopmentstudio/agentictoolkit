---
id: b7397142-dfab-4ea4-983e-3f0fdcc17fac
title: useActivityHistory
domain: agentictoolkit://recipes/status-web-hooks-use-activity-history
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook for paginating server-side activity history with shed-row absorption
  and auto-budget
platforms:
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# useActivityHistory

## Overview

`useActivityHistory` is a React hook that manages the fetching and merging of historical activity rows beyond the live window, with built-in shed-row absorption and automatic pagination budget. It is used to expand a bounded live feed (capped at MAX_ACTIVITY_ROWS and floored 24h back) backward in time through a server-side cursor, re-ordering merged results by (at, id) comparator, and holding caught rows that age out of the live window during paging. The hook is enabled conditionally by an age-out filter and exposes methods to load older rows and reset the auto-fetch budget.

## Behavioral Requirements

- **hook-signature**: The hook accepts one argument `opts: { enabled: boolean, live: ActivityRow[] }` where `enabled` gates whether the hook operates at all, and `live` is the current live window's oldest-first rows.
- **return-type**: The hook returns `UseActivityHistoryResult` with fields `rows` (ActivityRow[]), `loadOlder` (() => void), `loading` (boolean), `exhausted` (boolean), `error` (boolean), `autoBudgetSpent` (boolean), and `resetAutoBudget` (() => void).
- **rows-state**: The hook MUST maintain an internal `rows` array holding all paged historical rows in oldest-first order by (at, id) comparator — where `at` is the ISO 8601 timestamp string and `id` is the string identifier, with `at` taking precedence and `id` breaking ties.
- **loading-state**: The hook MUST set `loading: true` the instant `loadOlder()` is called and `loading: false` after the page fetch settles (success or error), provided the component is mounted and the epoch has not changed.
- **loading-guard**: The hook MUST NOT start a new fetch while a page is already in flight; the re-entrancy guard is the `inFlight` ref (set synchronously when a request starts), not the `loading` state.
- **exhausted-state**: The hook MUST set `exhausted: true` when the server returns a page with `nextCursor: null`, and MUST NOT attempt further fetches once exhausted until history is discarded by `enabled` going false.
- **exhausted-guard**: The hook MUST NOT start a new fetch if `exhausted` is already true.
- **error-state**: The hook MUST set `error: true` if a fetch fails (a non-ok response, a network error, a JSON parse failure, or the 20-second timeout abort) while the hook is still mounted and the epoch is unchanged, and MUST set `error: false` at the start of every `loadOlder()` call that passes its guards. An abort caused by unmount or by `enabled` going false does not set `error`.
- **error-does-not-prevent-retry**: When a page fails, the hook MUST NOT roll back the fetch count, advance the cursor, or mark the history as exhausted — the next `loadOlder()` call MUST retry the same window.
- **error-is-reported**: A failed page MUST set `error: true` so the pane can display an error message; silent errors would leave the UI stuck with no indication of failure.
- **cursor-initialization**: Whenever `cursorRef` is null (no page has yet succeeded since the last reset), `loadOlder()` MUST derive the request cursor from the live window's current oldest row as `{ atMs: Date.parse(liveOldest.at), id: liveOldest.id }`, or send no cursor if the live window is empty; this derived cursor is used for the request only and is not written to `cursorRef`.
- **cursor-from-live-tail**: The first page request MUST use the cursor derived from the live window's oldest row if available, and MUST use no cursor (null) if the live window is empty, causing the server to serve the newest page it has.
- **cursor-from-server**: Subsequent pages MUST use `nextCursor` returned in the previous page's response, or leave the cursor null if `nextCursor` was null (which marks exhausted).
- **page-size-constant**: Every page request MUST use a hard-coded page size of 300 rows (PAGE_SIZE constant).
- **page-size-clamp**: The server clamps the page size to the same value; the client does not check how many rows a page holds — exhaustion is decided solely by `nextCursor` being null.
- **request-timeout**: Every page request MUST time out after 20 seconds (PAGE_TIMEOUT_MS = 20_000) and MUST abort the fetch and treat the timeout as an error.
- **timeout-is-error**: A timeout-induced abort MUST result in `error: true` and MUST NOT mark the history as exhausted or advance the cursor.
- **auto-continue-budget**: The hook MUST track the number of fetches started since the last budget reset (auto-continued or not) in `fetchesRef` and MUST NOT call the fetch if `fetchesRef >= MAX_AUTOPAGE_FETCHES` (5).
- **auto-budget-tracking**: The hook MUST increment `fetchesRef` by 1 at the start of each fetch and MUST set `autoBudgetSpent: true` when `fetchesRef >= MAX_AUTOPAGE_FETCHES` after the increment.
- **auto-budget-reset**: The hook MUST expose `resetAutoBudget()` which sets `fetchesRef` to 0 and `autoBudgetSpent` to false, allowing the pane to continue fetching after the reader performs another scroll gesture.
- **merge-strategy-incoming-wins**: When merging an incoming page with previously loaded rows, if two rows share the same `id`, the incoming copy (from the page) MUST be kept and the previous copy MUST be discarded.
- **merge-sorting**: After merging, the entire combined array MUST be sorted by (at, id) in oldest-first order (byAtThenId comparator).
- **merge-identity-preservation**: If every incoming row already has a held row with the same `id` whose own keys and values are all strictly equal (a shallow, per-field `===` comparison), or the incoming list is empty, the merge MUST return the previous `rows` array unchanged to preserve referential identity.
- **merge-no-duplicates**: After merging, the returned array MUST have exactly one row per unique `id`, even if an `id` appears in both the live shed and a paged row.
- **shed-absorption-enabled**: Once the first request has gone out (tracked by `pagedRef`) and while `enabled` is true, the hook MUST, each time `live` or `enabled` changes, compare the previous live window with the new one for rows that fall off the OLD end and MUST capture those shed rows into the history array without requiring an additional fetch.
- **shed-absorption-guards**: A row is considered shed only if: (1) its `id` is no longer in the live window, (2) it sorts strictly before the new live window's oldest row using the (at, id) comparator, and (3) its `tone` field is not "progress".
- **shed-no-progress**: The hook MUST NOT capture rows with `tone: "progress"` even if they appear to have aged out, because such rows assert ongoing work that should not be frozen.
- **shed-not-empty-window**: An empty live window (length 0) MUST NOT trigger shed absorption; this condition indicates stale data or a transient API outage and the previous window MUST be retained for the next frame.
- **shed-only-after-paging**: Shed rows MUST NOT be captured until `pagedRef: true` (the first fetch has been initiated), because there is no history to hole before the reader has paged.
- **shed-merge-with-existing**: Shed rows MUST be merged into the existing `rows` array using the same merge strategy as paged rows (incoming-wins, sort, de-duplicate).
- **enabled-filtering**: When `enabled: false`, the hook MUST discard all loaded history and reset all state in an effect that runs after that render — `rows: []`, `loading: false`, `exhausted: false`, `error: false`, `autoBudgetSpent: false`, cursor null, fetch count 0, the exhausted and in-flight latches cleared, `pagedRef: false`, abort any in-flight request, and increment the epoch to invalidate any pending response.
- **enabled-state-clear**: Discarding history when `enabled: false` MUST happen via a useEffect dependency on `enabled`, not at call time.
- **epoch-validation**: Every completed fetch MUST check that `epoch.current === myEpoch` before updating state; if the epoch has changed (`enabled` went false after the request started), the response MUST be discarded entirely, and the `finally` block MUST NOT clear `inFlight` or `loading`.
- **epoch-increment**: The epoch MUST be incremented by 1 every time the reset effect runs with `enabled` false — on a true-to-false transition, and also on mount when the hook starts disabled.
- **abort-on-unmount**: When the component unmounts, the hook MUST abort any in-flight AbortController to clean up the fetch.
- **mount-tracking**: The hook MUST track `mounted.current`, and the async fetch path MUST NOT call setState after unmount.
- **api-client-ref**: The hook MUST read the `useStatusApi()` client through `apiRef.current` (not closed over directly) so that `loadOlder()` preserves a stable identity across client updates.
- **url-query-params**: A fetch request MUST go to the relative path `/activity` through the `useStatusApi()` client (which resolves it against its base path, `/api` by default) and MUST include a query parameter `limit=300` and, if the cursor is not null, MUST include `before` (the cursor's timestamp in milliseconds) and `beforeId` (the cursor's id string).
- **response-type**: The response body is parsed with `res.json()` and typed, without runtime schema validation, as `ActivityPage` with shape `{ rows: ActivityRow[], nextCursor: ActivityCursor | null }` where `ActivityCursor` is `{ atMs: number, id: string }`.
- **request-headers**: Each fetch request MUST include `headers: { accept: "application/json" }`.
- **error-status-code**: If the response is not ok (`!res.ok`), the hook MUST throw an error and treat it as a failed page (do not advance cursor or mark exhausted).
- **json-parse-error**: If the response body cannot be parsed as JSON, the hook MUST throw an error and treat it as a failed page.
- **loadOlder-stable-identity**: The `loadOlder` function MUST maintain a stable reference (the same function object) for the lifetime of the hook, achieved by wrapping it in `useCallback` with an empty dependency array.
- **resetAutoBudget-stable-identity**: The `resetAutoBudget` function MUST maintain a stable reference for the lifetime of the hook, achieved by wrapping it in `useCallback` with an empty dependency array.
- **no-localStorage**: The hook MUST NOT persist history, cursor, or any state to localStorage or any durable client store; all state is in-memory and is discarded on page reload or when `enabled: false`.
- **no-cap-history-array**: The hook MUST NOT impose a maximum size limit on the `rows` array; its size is implicitly bounded by the reader's ability to scroll and the 90-day server retention window.
- **uncapped-justification**: An uncapped array is correct because the array's size is bounded by what the reader can actually reach (a page costs a scroll gesture plus a budget reset), sorting large arrays (a few thousand rows) takes milliseconds, and evicting rows would create holes in the middle of the feed that the shed-absorption effect works to prevent.

## Appearance

Not applicable — this is a React hook managing in-memory state and server communication, not a visual component.

## States

Not applicable — this is a React hook managing in-memory state and server communication, not a visual component.

## Accessibility

Not applicable — this is a React hook managing in-memory state and server communication, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vector-001 | hook-signature, return-type, rows-state, no-localStorage | Call `useActivityHistory({ enabled: true, live: [] })` | Returns object with fields `{ rows: [], loadOlder: function, loading: false, exhausted: false, error: false, autoBudgetSpent: false, resetAutoBudget: function }` |
| vector-002 | loading-state, page-size-constant, cursor-from-live-tail | Live window contains one row `{ id: "a", at: "2026-09-24T10:00:00Z", tone: "ok" }`; call `loadOlder()`; server responds with 300 rows after 0.5s | `loading: true` immediately after call; request URL includes `limit=300&before=<timestamp>&beforeId=a`; `loading: false` after response; `rows` contains the 300 new rows |
| vector-003 | merge-strategy-incoming-wins, merge-sorting, merge-identity-preservation | Load page with rows `[{ id: "x", at: "2026-09-24T08:00:00Z" }]`; then load second page with rows `[{ id: "x", at: "2026-09-24T08:00:01Z" }, { id: "y", at: "2026-09-24T07:00:00Z" }]` | Final `rows` contains two entries: `id: "x"` with the newer `at`, and `id: "y"`; both sorted by (at, id); previous rows array is not modified if incoming rows were identical |
| vector-004 | error-state, error-does-not-prevent-retry, error-is-reported | Fetch request times out after 20s; next `loadOlder()` is called | `error: true` is set after timeout; cursor is not advanced; next call retries the same page; `error: false` as soon as the next call starts |
| vector-005 | auto-continue-budget, auto-budget-tracking, auto-budget-reset | Call `loadOlder()` six times without resetting budget, each after the previous page settles with a non-null `nextCursor` | First five calls proceed; sixth call returns immediately without fetch; `autoBudgetSpent: true` as soon as the fifth call starts; after `resetAutoBudget()`, the seventh call proceeds |
| vector-006 | exhausted-state, exhausted-guard, cursor-from-server | Load a page with `nextCursor: null` | `exhausted: true` is set; subsequent calls to `loadOlder()` return immediately without fetching |
| vector-007 | shed-absorption-enabled, shed-absorption-guards, shed-no-progress | Live window `[{ id: "a", at: "2026-09-24T10:00:00Z", tone: "ok" }, { id: "b", at: "2026-09-24T11:00:00Z", tone: "ok" }]`; call `loadOlder()`; live window then updates to `[{ id: "b", at: "2026-09-24T11:00:00Z", tone: "ok" }]` | Shed row `{ id: "a", ... }` is merged into `rows` without a fetch; had row `a` carried `tone: "progress"`, it would not be captured |
| vector-008 | enabled-filtering, epoch-validation, abort-on-unmount | Set `enabled: false` while a fetch is in-flight | History array is cleared to `[]`; in-flight fetch is aborted; any response to the aborted fetch is discarded; state is reset to defaults |
| vector-009 | loadOlder-stable-identity | Capture the `loadOlder` reference; re-render the hook with a new `live` prop; capture it again | Both references are the same object |
| vector-010 | request-headers, response-type | Call `loadOlder()`; server responds with `{ rows: [...], nextCursor: { atMs: 1234567890, id: "next" } }` | Request header includes `accept: application/json`; `rows` state is updated; `cursorRef` is set to the returned cursor |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | — | When false, history is discarded and `loadOlder()` returns without fetching. Required; caller decides whether the age-out filter is active. |
| `live` | ActivityRow[] | — | The current live window's oldest-first rows from `board.activity` (or equivalent live feed). Required; the hook uses this to derive the cursor and detect shed rows. |
| PAGE_SIZE | number | 300 | Hard-coded page size; every request asks for 300 rows. The server clamps to the same value. |
| PAGE_TIMEOUT_MS | number | 20000 | Hard-coded timeout in milliseconds; every fetch aborts if it does not settle within 20 seconds. |
| MAX_AUTOPAGE_FETCHES | number | 5 | Hard-coded auto-fetch budget; `loadOlder()` returns without fetching once this many fetches have started since the last `resetAutoBudget()`. Exported. |

## Deep Linking

Not applicable: this is a non-UI hook with no routes or URL paths.

## Localization

Not applicable: the hook surfaces no user-facing strings; its only string, the English `activity fetch failed: <status>` error message, is thrown and caught internally and never shown — the caller renders its own text from the `error` boolean.

## Accessibility Options

Not applicable: this is a non-UI hook with no visual display or interaction states.

## Feature Flags

Not applicable: the hook has no built-in feature flags; the caller gates it via the `enabled` prop.

## Analytics

Not applicable: the hook surfaces no analytics events; the caller can wrap `loadOlder()` to log usage if needed.

## Privacy

Not applicable: the hook holds no persistent user data; all state is in-memory and request URLs contain only the cursor and page size.

## Logging

Not applicable: the hook makes no log calls; a caught fetch error, including its status-code message, is discarded and only the `error` boolean is surfaced.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

**Unit Test Coverage**: `use-activity-history.dom.test.tsx` beside the hook covers disabled fetching, paging from the live tail's oldest row, the `before`/`beforeId` cursor pair, de-duplication, the MAX_AUTOPAGE_FETCHES budget, discarding history on disable, dropping a page that lands after a discard, error reporting without exhaustion, clearing the error on the next attempt, keeping the cursor after a failure, the shed-absorption guards (paged-only, OLD-end only, never `progress`, empty window as outage), and incoming-copy-wins replacement. The tests isolate the network by stubbing the global `fetch` that the default `useStatusApi()` client calls.

**Separation of Concerns**: The hook separates state management (useState for render-driven fields, useRef for stable-identity closures), side effects (shed absorption useEffect, cleanup on unmount), networking (fetch, timeout, abort), and data transformation (merge, sort). Each concern is addressable independently; a port can replace the networking layer without touching state logic.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
