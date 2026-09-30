<!-- leaf: implement-status-web-hooks/use-live-snapshot--test-vectors · source: status-web-hooks-use-live-snapshot.md -->

# useLiveSnapshot

## Conformance Test Vectors

Vectors 001–004 come from `use-live-snapshot.test.ts`; 005–011 from `use-live-snapshot.dom.test.tsx` (a mock `EventSource`, stubbed `fetch`, `__resetStoreForTests()` after each case); the rest are derived from the source.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-live-snapshot-001 | same-snapshot-null | `isSameSnapshot(null, snap("2026-06-30T00:00:00.000Z"))` | `false` |
| use-live-snapshot-002 | same-snapshot-identity | `isSameSnapshot(s, s)` | `true` |
| use-live-snapshot-003 | same-snapshot-clock | two distinct snapshots, both `generatedAt` `2026-06-30T00:00:00.000Z` | `true` |
| use-live-snapshot-004 | same-snapshot-clock | `generatedAt` `2026-06-30T00:00:00.000Z` vs `2026-06-30T00:01:00.000Z` | `false` |
| use-live-snapshot-005 | stream-path, stream-open-event, snapshot-frame, ingest-update | mount; stream fires `open` then `snapshot` with `generatedAt` `2030-01-01T00:00:00.000Z` and one service | stream URL `/api/live/stream`; `snapshot.generatedAt` equals that value; `snapshot.services` length 1 |
| use-live-snapshot-006 | schedule-frame, result-next-poll-streaming | stream `open`, then `schedule` with `{"nextCheckAt":"2030-06-01T00:00:00.000Z"}` | `nextPollAt` equals `Date.parse("2030-06-01T00:00:00.000Z")` |
| use-live-snapshot-007 | check-start, check-post-sync, result-polling, check-resolve | stream open, initial poll settled; call `refresh()`; then push a snapshot with `generatedAt` now + 5 s | `fetch` called with `("/api/live/check", { method: "POST" })` synchronously; `polling` true; after the push `polling` false |
| use-live-snapshot-008 | check-safety | fake timers; `refresh()` with `ran: true`; advance 60 000 ms; then push a snapshot built now + 90 s | `polling` still true after 60 s; false after the push |
| use-live-snapshot-009 | check-started-no-refetch | no stream opened; poll settled; `fetch` mock cleared; `refresh()` with `ran: true` | zero `GET /api/live` calls after the POST |
| use-live-snapshot-010 | stream-closed-error, stream-reopen | fake timers; mount; fire `error` with `readyState` `CLOSED`; advance 3 000 ms | 2 `EventSource` instances created |
| use-live-snapshot-011 | stream-transient-error | fake timers; mount; fire `error` with `readyState` `CONNECTING`; advance 10 000 ms | 1 `EventSource` instance |
| use-live-snapshot-012 | check-not-ran, check-not-ran-refetch | stream not connected; `refresh()`; POST returns 200 `{ "ran": false }` | `polling` returns to false once the poll settles; one `GET /api/live` issued after the POST |
| use-live-snapshot-013 | fetch-http-error, fetch-failure-sets-error, result-offline, result-disconnected, result-offline-detail | no stream; `GET /api/live` returns 503 on every call; query settles | `offline` true; `disconnected` true; `offlineDetail` `"live 503"` |
| use-live-snapshot-014 | fetch-success-clears-error, live-error-sticky | after 013, next `GET /api/live` returns 200 with a snapshot | `offlineDetail` null; `disconnected` false; during the in-flight retry `disconnected` stayed true while `offline` was false |
| use-live-snapshot-015 | result-blind | ingest a snapshot with `services: []` | `blind` true; with one service `blind` false; before any snapshot `blind` false |
| use-live-snapshot-016 | check-unrelated-push | `refresh()` with `ran: true`; push a snapshot with `generatedAt` one minute before the click | `snapshot` updated; `polling` stays true |
| use-live-snapshot-017 | snapshot-frame-malformed | stream fires `snapshot` with data `not json` | no throw; `snapshot` unchanged; no frame subscriber called |
| use-live-snapshot-018 | ingest-once, frame-subscribe | subscribe a counter via `subscribeLiveFrames`; ingest the same snapshot from the stream and then from the poll | counter is 1 |
| use-live-snapshot-019 | stream-ref-count, stream-single, stream-release | mount two hooks under one client; unmount one; unmount the other | 1 `EventSource`; still open after the first unmount; closed after the second |
| use-live-snapshot-020 | client-estimate, result-next-poll-fallback | no stream; poll succeeds with `dataUpdatedAt` T | `nextPollAt` equals T + 60 000 |
