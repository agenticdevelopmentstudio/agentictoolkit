---
id: b7397142-dfab-4ea4-983e-3f0fdcc17fac
title: Activity History
domain: agentictoolkit://cookbook/status/dashboard/state/activity-history
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Paginates server-side activity history, with shed-row absorption and an
  auto-fetch budget
platforms:
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Activity History

## Overview

This logic manages the fetching and merging of historical activity rows beyond the live window, with built-in shed-row absorption and an automatic pagination budget. It expands a bounded live feed (capped at a fixed row count and floored 24 hours back) backward in time through a server-side cursor, re-ordering merged results by a timestamp-then-id comparator, and holding caught rows that age out of the live window during paging. This logic is enabled conditionally by an age-out filter and exposes methods to load older rows and reset the auto-fetch budget.

## Behavioral Requirements

- **hook-signature**: This logic takes one argument carrying `enabled` (boolean; gates whether it operates at all) and `live` (a list of activity rows — the current live window's oldest-first rows).
- **return-type**: This logic returns an object with fields `rows` (a list of activity rows), `loadOlder` (a callback that takes no arguments), `loading` (boolean), `exhausted` (boolean), `error` (boolean), `autoBudgetSpent` (boolean), and `resetAutoBudget` (a callback that takes no arguments).
- **rows-state**: This logic MUST maintain an internal `rows` list holding all paged historical rows in oldest-first order by a timestamp-then-id comparator — where `at` is the ISO 8601 timestamp string and `id` is the string identifier, with `at` taking precedence and `id` breaking ties.
- **loading-state**: This logic MUST set `loading: true` the instant `loadOlder` is called and `loading: false` after the page fetch settles (success or error), provided the hook instance is still active and the epoch has not changed.
- **loading-guard**: This logic MUST NOT start a new fetch while a page is already in flight; the re-entrancy guard is an internal in-flight flag (set synchronously when a request starts), not the `loading` field.
- **exhausted-state**: This logic MUST set `exhausted: true` when the server returns a page whose `nextCursor` field is `null`, and MUST NOT attempt further fetches once exhausted until history is discarded by `enabled` going false.
- **exhausted-guard**: This logic MUST NOT start a new fetch if `exhausted` is already true.
- **error-state**: This logic MUST set `error: true` if a fetch fails (a non-OK response, a network error, a JSON parse failure, or the 20-second timeout abort) while the hook instance is still active and the epoch is unchanged, and MUST set `error: false` at the start of every `loadOlder` call that passes its guards. An abort caused by teardown or by `enabled` going false does not set `error`.
- **error-does-not-prevent-retry**: When a page fails, this logic MUST NOT roll back the fetch count, advance the cursor, or mark the history as exhausted — the next `loadOlder` call MUST retry the same window.
- **error-is-reported**: A failed page MUST set `error: true` so the pane can display an error message; silent errors would leave the UI stuck with no indication of failure.
- **cursor-initialization**: Whenever no page has yet succeeded since the last reset, `loadOlder` MUST derive the request cursor from the live window's current oldest row as a millisecond timestamp parsed from that row's `at` field plus that row's `id`, or send no cursor if the live window is empty; this derived cursor is used for the request only and is not written to the internal cursor state.
- **cursor-from-live-tail**: The first page request MUST use the cursor derived from the live window's oldest row if available, and MUST use no cursor if the live window is empty, causing the server to serve the newest page it has.
- **cursor-from-server**: Subsequent pages MUST use `nextCursor` returned in the previous page's response, or leave the cursor null if `nextCursor` was null (which marks exhausted).
- **page-size-constant**: Every page request MUST use a hard-coded page size of 300 rows.
- **page-size-clamp**: The server clamps the page size to the same value; the client does not check how many rows a page holds — exhaustion is decided solely by `nextCursor` being null.
- **request-timeout**: Every page request MUST time out after 20 seconds and MUST abort the fetch and treat the timeout as an error.
- **timeout-is-error**: A timeout-induced abort MUST result in `error: true` and MUST NOT mark the history as exhausted or advance the cursor.
- **auto-continue-budget**: This logic MUST track the number of fetches started since the last budget reset (auto-continued or not) and MUST NOT start a fetch once that count reaches 5.
- **auto-budget-tracking**: This logic MUST increment the fetch counter by 1 at the start of each fetch and MUST set `autoBudgetSpent: true` when that counter reaches 5 after the increment.
- **auto-budget-reset**: This logic MUST expose `resetAutoBudget`, which sets the fetch counter to 0 and `autoBudgetSpent` to false, allowing the pane to continue fetching after the reader performs another scroll gesture.
- **merge-strategy-incoming-wins**: When merging an incoming page with previously loaded rows, if two rows share the same `id`, the incoming copy (from the page) MUST be kept and the previous copy MUST be discarded.
- **merge-sorting**: After merging, the entire combined list MUST be sorted by the timestamp-then-id comparator in oldest-first order.
- **merge-identity-preservation**: If every incoming row already has a held row with the same `id` whose own keys and values are all exactly equal (a shallow, per-field comparison), or the incoming list is empty, the merge MUST return the previous `rows` list unchanged to preserve referential identity.
- **merge-no-duplicates**: After merging, the returned list MUST have exactly one row per unique `id`, even if an `id` appears in both the live shed and a paged row.
- **shed-absorption-enabled**: Once the first request has gone out and while `enabled` is true, this logic MUST, each time `live` or `enabled` changes, compare the previous live window with the new one for rows that fall off the OLD end and MUST capture those shed rows into the history list without requiring an additional fetch.
- **shed-absorption-guards**: A row is considered shed only if: (1) its `id` is no longer in the live window, (2) it sorts strictly before the new live window's oldest row using the timestamp-then-id comparator, and (3) its `tone` field is not "progress".
- **shed-no-progress**: This logic MUST NOT capture rows with `tone: "progress"` even if they appear to have aged out, because such rows assert ongoing work that should not be frozen.
- **shed-not-empty-window**: An empty live window (length 0) MUST NOT trigger shed absorption; this condition indicates stale data or a transient API outage and the previous window MUST be retained for the next frame.
- **shed-only-after-paging**: Shed rows MUST NOT be captured until the first fetch has been initiated, because there is no history to hole before the reader has paged.
- **shed-merge-with-existing**: Shed rows MUST be merged into the existing `rows` list using the same merge strategy as paged rows (incoming-wins, sort, de-duplicate).
- **enabled-filtering**: When `enabled: false`, this logic MUST discard all loaded history and reset all state after that render — `rows` empty, `loading: false`, `exhausted: false`, `error: false`, `autoBudgetSpent: false`, cursor null, fetch count 0, the exhausted and in-flight latches cleared, the has-paged flag cleared, abort any in-flight request, and increment the epoch to invalidate any pending response.
- **enabled-state-clear**: Discarding history when `enabled: false` MUST happen through a reaction to `enabled` changing, not at call time.
- **epoch-validation**: Every completed fetch MUST check that the epoch is still the same value captured when the request started, before updating state; if the epoch has changed (`enabled` went false after the request started), the response MUST be discarded entirely, and the completion step MUST NOT clear the in-flight flag or `loading`.
- **epoch-increment**: The epoch MUST be incremented by 1 every time the reset runs with `enabled` false — on a true-to-false transition, and also on first use when the hook starts disabled.
- **abort-on-unmount**: When the hook instance is torn down, this logic MUST abort any in-flight request to clean up the fetch.
- **mount-tracking**: This logic MUST track whether the hook instance is still active, and the async fetch path MUST NOT update state after teardown.
- **api-client-ref**: This logic MUST read the API client through an internal reference (not closed over directly) so that `loadOlder` preserves a stable identity across client updates.
- **url-query-params**: A fetch request MUST go to the relative path `/activity` through the API client (which resolves it against its base path, `/api` by default) and MUST include a query parameter `limit=300` and, if the cursor is not null, MUST include `before` (the cursor's timestamp in milliseconds) and `beforeId` (the cursor's id string).
- **response-type**: The response body is parsed as JSON, without runtime schema validation, as a page shape carrying `rows` (a list of activity rows) and `nextCursor` (a cursor or `null`), where a cursor carries `atMs` (a number) and `id` (a string).
- **request-headers**: Each fetch request MUST include the header `accept: application/json`.
- **error-status-code**: If the response is not OK, this logic MUST throw an error and treat it as a failed page (do not advance cursor or mark exhausted).
- **json-parse-error**: If the response body cannot be parsed as JSON, this logic MUST throw an error and treat it as a failed page.
- **loadOlder-stable-identity**: The `loadOlder` function MUST maintain a stable reference (the same function object) for the lifetime of the hook instance (see Platform Notes for how the source achieves this).
- **resetAutoBudget-stable-identity**: The `resetAutoBudget` function MUST maintain a stable reference for the lifetime of the hook instance (see Platform Notes for how the source achieves this).
- **no-persistent-storage**: This logic MUST NOT persist history, cursor, or any state to durable client storage; all state is in-memory and is discarded on page reload or when `enabled: false`.
- **no-cap-history-array**: This logic MUST NOT impose a maximum size limit on the `rows` list; its size is implicitly bounded by the reader's ability to scroll and the 90-day server retention window.
- **uncapped-justification**: An uncapped list is correct because its size is bounded by what the reader can actually reach (a page costs a scroll gesture plus a budget reset), sorting large lists (a few thousand rows) takes milliseconds, and evicting rows would create holes in the middle of the feed that the shed-absorption effect works to prevent.

## Appearance

Not applicable — this logic manages in-memory state and server communication, not a visual component.

## States

Not applicable — this logic manages in-memory state and server communication, not a visual component.

## Accessibility

Not applicable — this logic manages in-memory state and server communication, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vector-001 | hook-signature, return-type, rows-state, no-persistent-storage | This logic called with `enabled: true` and an empty live window | Returns an object with `rows` empty, `loadOlder` and `resetAutoBudget` as callbacks, and `loading`, `exhausted`, `error`, `autoBudgetSpent` all `false` |
| vector-002 | loading-state, page-size-constant, cursor-from-live-tail | Live window contains one row with `id: "a"`, `at: "2026-09-24T10:00:00Z"`, `tone: "ok"`; `loadOlder` is called; the server responds with 300 rows after 0.5s | `loading: true` immediately after the call; the request URL includes `limit=300&before=<timestamp>&beforeId=a`; `loading: false` after the response; `rows` contains the 300 new rows |
| vector-003 | merge-strategy-incoming-wins, merge-sorting, merge-identity-preservation | A page with one row (`id: "x"`, `at: "2026-09-24T08:00:00Z"`) is loaded; then a second page with two rows (`id: "x"`, `at: "2026-09-24T08:00:01Z"` and `id: "y"`, `at: "2026-09-24T07:00:00Z"`) is loaded | Final `rows` contains two entries: `id: "x"` with the newer `at`, and `id: "y"`; both sorted by the timestamp-then-id comparator; the previous rows list is not replaced if the incoming rows were identical |
| vector-004 | error-state, error-does-not-prevent-retry, error-is-reported | A fetch request times out after 20 seconds; `loadOlder` is called again | `error: true` is set after the timeout; the cursor is not advanced; the next call retries the same page; `error: false` as soon as the next call starts |
| vector-005 | auto-continue-budget, auto-budget-tracking, auto-budget-reset | `loadOlder` is called six times without resetting the budget, each after the previous page settles with a non-null next cursor | The first five calls proceed; the sixth call returns immediately without fetching; `autoBudgetSpent: true` as soon as the fifth call starts; after `resetAutoBudget` is called, the seventh call proceeds |
| vector-006 | exhausted-state, exhausted-guard, cursor-from-server | A page with a `null` next cursor is loaded | `exhausted: true` is set; subsequent calls to `loadOlder` return immediately without fetching |
| vector-007 | shed-absorption-enabled, shed-absorption-guards, shed-no-progress | Live window holds two rows (`id: "a"`, `at: "2026-09-24T10:00:00Z"`, `tone: "ok"` and `id: "b"`, `at: "2026-09-24T11:00:00Z"`, `tone: "ok"`); `loadOlder` is called; the live window then updates to hold only `id: "b"` | The shed row `id: "a"` is merged into `rows` without a fetch; had row `a` carried `tone: "progress"`, it would not have been captured |
| vector-008 | enabled-filtering, epoch-validation, abort-on-unmount | `enabled` is set to `false` while a fetch is in flight | The history list is cleared to empty; the in-flight fetch is aborted; any response to the aborted fetch is discarded; state is reset to defaults |
| vector-009 | loadOlder-stable-identity | The `loadOlder` reference is captured; the hook is re-rendered with a new `live` value; the reference is captured again | Both references are the same function object |
| vector-010 | request-headers, response-type | `loadOlder` is called; the server responds with a page carrying rows and a next cursor of `atMs: 1234567890`, `id: "next"` | The request includes the header `accept: application/json`; `rows` is updated; the internal cursor is set to the returned cursor |

## Edge Cases

- **empty-live-window**: When the live window is empty on the first call to `loadOlder`, this logic MUST request with no cursor, causing the server to serve the newest page it has. No error is raised; this case is explicitly supported for quiet fleets whose 24h window holds nothing.
- **live-window-aged-past-history**: Before the reader has paged, rows the live window sheds are let go (the record of the previous live window still advances); the first page then starts from wherever the window's oldest row has moved to, so no gap forms.
- **live-window-becomes-empty**: If the live window becomes empty in a render (indicating stale data or an API blip), the shed effect MUST NOT trigger; the previous window is retained. The next render with a non-empty window resumes shed absorption.
- **fetch-timeout-20-seconds**: Any fetch that does not settle within 20 seconds (whether dropped connection, proxy holding socket, laptop suspended, or unresponsive server) MUST be aborted and treated as an error. The timeout is not retried automatically; the next `loadOlder` call retries the same window.
- **row-id-collision-merge**: If the same `id` appears in both the previous `rows` and an incoming page, the incoming copy is kept and the previous is discarded. If incoming is byte-identical to previous, the list is not mutated.
- **concurrent-enabled-false-and-fetch**: If `enabled` goes false while a fetch is in flight, the request is aborted and the epoch increments; if the hook instance is torn down, the request is aborted and it stops being tracked as active. Either way a response that still lands is dropped by the epoch/active check before updating `rows`, and a request started after a re-enable keeps its own latch because the stale completion step skips clearing the in-flight/loading flags.
- **shed-row-no-longer-live**: A row is shed only if it no longer appears in the live window by `id` AND it sorts before the window's oldest row. A row that leaves without sorting behind what the window still holds (for example a superseded `deploying` deployment whose row stops being derived, or an endpoint disabled or renamed) is not captured, and a `progress` row is never captured, avoiding freezing a still-changing row.
- **no-automatic-retry-on-error**: Errors are not automatically retried; they are reported in `error: true` and the pane is responsible for calling `loadOlder` again in response to user scroll.
- **history-reset-on-reenable**: History is discarded the moment `enabled` goes false (the age-out filter comes back on) and is NOT restored when `enabled` returns to true; it is invisible under any TTL, and keeping it would make the memory cost of a scroll permanent for the session.
- **budget-independent-of-success**: The auto-fetch budget is incremented at the start of each call, not after success. A page that fails still consumes one budget slot; this prevents a broken endpoint from being retried infinitely by the auto-continue behavior.
- **null-oldest-handling**: When the live window's first row is absent, this logic treats the oldest row as absent: the shed effect returns early without updating its record of the previous live window, and `loadOlder` sends no cursor if none has been derived yet either. No crash occurs.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | — | When false, history is discarded and `loadOlder` returns without fetching. Required; caller decides whether the age-out filter is active. |
| `live` | a list of activity rows | — | The current live window's oldest-first rows from the board's activity feed (or equivalent). Required; this logic uses it to derive the cursor and detect shed rows. |
| Page size | number | 300 | Hard-coded page size; every request asks for 300 rows. The server clamps to the same value. |
| Page timeout | milliseconds | 20000 | Hard-coded timeout; every fetch aborts if it does not settle within 20 seconds. |
| Auto-page fetch budget | number | 5 | Hard-coded auto-fetch budget; `loadOlder` returns without fetching once this many fetches have started since the last `resetAutoBudget` call. |

## Deep Linking

Not applicable: this is a non-UI hook with no routes or URL paths.

## Localization

Not applicable: this logic surfaces no user-facing strings; its only string, the English `activity fetch failed: <status>` error message, is thrown and caught internally and never shown — the caller renders its own text from the `error` boolean.

## Accessibility Options

Not applicable: this is a non-UI hook with no visual display or interaction states.

## Feature Flags

Not applicable: this logic has no built-in feature flags; the caller gates it via the `enabled` field.

## Analytics

Not applicable: this logic surfaces no analytics events; the caller can wrap `loadOlder` to log usage if needed.

## Privacy

Not applicable: this logic holds no persistent user data; all state is in-memory and request URLs contain only the cursor and page size.

## Logging

Not applicable: this logic makes no log calls; a caught fetch error, including its status-code message, is discarded and only the `error` boolean is surfaced.

## Platform Notes

- **React/Web**: The hook uses standard React primitives (`useState`, `useRef`, `useEffect`, `useCallback`) and the Fetch API with `AbortController`. The stable identity required of `loadOlder` and `resetAutoBudget` comes from wrapping each in `useCallback` with an empty dependency array; the in-flight, cursor, fetch-count, has-paged, active-instance, and epoch tracking are plain `useRef`s that persist across renders without causing them. The auto-page fetch budget constant is also exported from the module for callers that need the exact number. A port to another platform MUST provide equivalent state management (mutable refs for stable-identity closures, reactive state for render-triggering values), equivalent async/await with cancellation, and equivalent object/list operations for merge sorting. The timestamp-then-id comparator works with any language's string and number types. Error handling relies on try/catch and the response object's `ok` boolean.
- **React Native / TypeScript / Node.js**: Equivalent implementations use the same Fetch API or a polyfill; `AbortController` is available in Node 15+. Replace `useStatusApi()` with the platform-equivalent HTTP client. All logic for merging, shed detection, cursor state, and budget counting is platform-agnostic.
- **Swift / iOS / macOS**: A port would use `@State` properties for `rows`, `loading`, `exhausted`, `error`, `autoBudgetSpent`; plain stored (non-`@State`) properties for cursor, fetch count, flags, abort, and epoch; `URLSession` with `DispatchSourceTimer` or `Task.sleep` for the 20-second timeout; and a publisher-based refresh loop (Combine or async/await) to drive the shed effect when `live` changes. The merge, sort, and guard logic is identical.
- **Kotlin / Android**: A port would use `mutableStateOf` in Compose or `StateFlow`/`LiveData` in traditional Android; `kotlinx.coroutines.Job` and `withTimeoutOrNull` for timeout; `OkHttpClient` for the network request; and a `LaunchedEffect` or `CoroutineScope` to drive the shed effect. Replace `useStatusApi()` with the platform's HTTP client.
- **C# / WinUI 3**: A port would use `ObservableCollection<ActivityRow>` for `rows`, `bool` properties with `INotifyPropertyChanged` for state, `System.Net.Http.HttpClient` with `CancellationTokenSource` for timeout, `Task.Delay` for the 20-second timeout, and `PropertyChanged` events to drive the shed effect. The XAML binding system replaces React's hook dependency tracking. Merge and cursor logic is identical. No localStorage equivalent is needed (in-memory only).

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-activity-history.ts` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
