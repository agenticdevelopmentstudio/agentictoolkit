<!-- leaf: implement-status-web-hooks/use-live-snapshot--edge-cases · source: status-web-hooks-use-live-snapshot.md -->

# useLiveSnapshot

**Rules** (cite as `implement-status-web-hooks/use-live-snapshot--edge-cases#<slug>`):

- `nothing-received-yet` MUST — snapshot MUST be null, blind false, offline false, and nextPollAt null until the first poll completes.
- `server-rendering` MUST — No stream MUST open (no window); getServerView() returns the fresh view, so SSR shows the pre-anything state.
- `stream-open-before-first-schedule-frame` MUST — nextPollAt MUST fall back to the client estimate.
- `schedule-frame-with-nextcheckat-null` MUST — nextCheckAt MUST become null, and nextPollAt falls back to the client estimate.
- `schedule-frame-with-an-unparseable-date-string` MUST — The JSON parses, Date.parse yields NaN, and nextPollAt MUST be NaN (the ?? fallback does not replace NaN); because NaN …
- `snapshot-with-an-unparseable-generatedat` MUST — It MUST be ingested, but it cannot resolve a pending check (NaN >= t is false); the safety timer clears the spinner.
- `malformed-snapshot-or-schedule-frame` MUST — MUST be dropped silently, as declared in the source comments; recovery comes from the next frame or the poll.
- `re-delivered-frame` MUST — A frame with the same generatedAt as the last ingested MUST be skipped, including a poll result racing a stream push of …
- `out-of-order-frames` MUST — A snapshot with an older generatedAt than the last ingested MUST still replace snapshot; only equality is checked.
- `backend-unreachable` MUST — The poll MUST set liveError to the fetch error's message after one retry; with the stream down, disconnected is true …
- `auth-expiry-or-5xx-on-stream-connect` MUST — The browser closes the source; the store MUST reopen it every 3 000 ms for as long as it is referenced, with no backoff …
- `transient-network-drop-on-the-stream` MUST — The browser reconnects on its own; the store MUST only mark streamConnected false, which re-enables the poll and …
- `last-subscriber-unmounts-during-a-pending-reopen` MUST — The reopen MUST be cancelled and no new source opened.
- `check-post-fails` MUST — The spinner MUST clear at once; no error is surfaced to the caller.
- `check-post-ok-with-a-non-json-body` MUST — MUST count as started (body is null, so ran is not false).
- `check-started-but-its-snapshot-never-arrives` MUST — The spinner MUST clear after 200 000 ms and a re-read MUST be issued.
- `reset-with-a-check-in-flight` MAY — The in-flight POST continuation is not cancelled; when it completes it MAY patch the fresh view and MAY start a new …
- `hung-get-live-or-post` MUST — No client timeout MUST apply; polling stays true while the query fetches.

## Edge Cases

- **Nothing received yet**: `snapshot` MUST be null, `blind` false, `offline` false, and `nextPollAt` null until the first poll completes.
- **Server rendering**: No stream MUST open (no `window`); `getServerView()` returns the fresh view, so SSR shows the pre-anything state.
- **Stream open before first schedule frame**: `nextPollAt` MUST fall back to the client estimate.
- **Schedule frame with `nextCheckAt: null`**: `nextCheckAt` MUST become null, and `nextPollAt` falls back to the client estimate.
- **Schedule frame with an unparseable date string**: The JSON parses, `Date.parse` yields `NaN`, and `nextPollAt` MUST be `NaN` (the `??` fallback does not replace `NaN`); because `NaN !== NaN`, each such frame MUST re-notify listeners.
- **Snapshot with an unparseable `generatedAt`**: It MUST be ingested, but it cannot resolve a pending check (`NaN >= t` is false); the safety timer clears the spinner.
- **Malformed snapshot or schedule frame**: MUST be dropped silently, as declared in the source comments; recovery comes from the next frame or the poll.
- **Re-delivered frame**: A frame with the same `generatedAt` as the last ingested MUST be skipped, including a poll result racing a stream push of the same cycle.
- **Out-of-order frames**: A snapshot with an older `generatedAt` than the last ingested MUST still replace `snapshot`; only equality is checked.
- **Backend unreachable (network error)**: The poll MUST set `liveError` to the fetch error's message after one retry; with the stream down, `disconnected` is true and `offline` is true between probes.
- **Auth expiry or 5xx on stream connect**: The browser closes the source; the store MUST reopen it every 3 000 ms for as long as it is referenced, with no backoff growth and no retry limit.
- **Transient network drop on the stream**: The browser reconnects on its own; the store MUST only mark `streamConnected` false, which re-enables the poll and triggers an immediate re-read.
- **Last subscriber unmounts during a pending reopen**: The reopen MUST be cancelled and no new source opened.
- **Check POST fails (network or non-OK)**: The spinner MUST clear at once; no error is surfaced to the caller.
- **Check POST OK with a non-JSON body**: MUST count as started (`body` is null, so `ran` is not false).
- **Check started but its snapshot never arrives (stream wedged)**: The spinner MUST clear after 200 000 ms and a re-read MUST be issued.
- **Two overlapping `refresh()` calls**: See the open question on overlapping-check-requests.
- **Two providers under one `QueryClient`**: See the open question on per-client-poll-isolation.
- **`reset()` with a check in flight**: The in-flight POST continuation is not cancelled; when it completes it MAY patch the fresh view and MAY start a new safety timer that later calls the captured re-read.
- **Hung `GET /live` or POST**: No client timeout MUST apply; `polling` stays true while the query fetches.
- **Concurrent access**: Single-threaded JS; synchronous store code cannot interleave, and the only async overlaps are those two open questions.
