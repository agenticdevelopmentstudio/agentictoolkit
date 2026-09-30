<!-- leaf: implement-hub-domain-2/projects--part-5 · source: hub-domain-projects.md -->

# Hub Domain: Projects — continued (part 5)

**Rules** (cite as `implement-hub-domain-2/projects--part-5#<slug>`):

- `live-payload-less-wake` MUST
- `live-one-connection-per-board-refcounted` MUST
- `live-reopens-after-going-quiet` MUST
- `live-coalesces-burst-into-one-wake` MUST
- `live-wakes-again-after-window-closes` MUST
- `live-poll-fallback-wakes-identically` MUST
- `live-unsubscribe-during-pending-wake-is-silent` MUST
- `live-last-unsubscribe-drops-pending-timer` MUST
- `live-onwake-read-at-fire-time-not-closed-over` MUST
- `live-null-project-id-subscribes-to-nothing` MUST

### live.ts — `subscribeToProject` / `useProjectLive`

- **live-payload-less-wake**: The `project` SSE event MUST carry no payload
  and no change kind; `subscribeToProject`'s `onWake` callback MUST take no
  arguments describing what changed — every subscriber re-reads through its
  own ordinary REST call under the RLS it already passes (file header).
- **live-one-connection-per-board-refcounted**: `subscribeToProject`
  MUST open exactly ONE `connectSse` connection per distinct `projectId`,
  shared by every subscriber, and MUST close it only when the LAST
  subscriber unsubscribes (confirmed by `hub-domain-projects-031`/`033`).
- **live-reopens-after-going-quiet**: Re-subscribing to a `projectId` after
  its connection was fully closed MUST open a fresh connection, never reuse
  the closed handle (confirmed by `hub-domain-projects-034`).
- **live-coalesces-burst-into-one-wake**: A burst of same-board `project`
  events within the 150ms trailing `COALESCE_MS` window MUST fold into
  exactly one `onWake` call per subscriber, never one call per event (file
  header, `wake`, confirmed by `hub-domain-projects-035`).
- **live-wakes-again-after-window-closes**: The coalescing guard MUST be a
  window, not a once-per-connection latch — a change arriving after a
  previous window already fired MUST produce a second `onWake` call
  (confirmed by `hub-domain-projects-036`).
- **live-poll-fallback-wakes-identically**: `connectSse`'s `onPoll` callback
  MUST wake subscribers exactly as a live SSE event does, at a
  `POLL_INTERVAL_MS` (60,000ms) cadence, so a board with no live connection
  still updates each session (file header, confirmed by
  `hub-domain-projects-037`).
- **live-unsubscribe-during-pending-wake-is-silent**: A subscriber that
  unsubscribes while a coalesced wake is pending MUST NOT receive that wake
  — the listener set is snapshotted at fire time (confirmed by
  `hub-domain-projects-038`/`039`).
- **live-last-unsubscribe-drops-pending-timer**: When the LAST subscriber
  of a board unsubscribes while a wake timer is pending, `subscribeToProject`
  MUST clear that timer and close the connection, rather than letting a
  stale timer fire against a torn-down entry (`subscribeToProject`'s
  returned unsubscribe function, confirmed by `hub-domain-projects-039`).
- **live-onwake-read-at-fire-time-not-closed-over**: `useProjectLive` MUST
  hold the latest `onWake` in a `ref` and read it at fire time, rather than
  naming it as an effect dependency — a caller whose `onWake` identity
  changes every render (a filter edit) MUST NOT tear down and reopen the
  shared connection on every keystroke (`useProjectLive`).
- **live-null-project-id-subscribes-to-nothing**: `useProjectLive(null |
  undefined, onWake)` MUST subscribe to nothing, so a pane may call it
  before its board has resolved (`useProjectLive` doc comment).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.workspace` (list/create, most clients) | `string \| undefined` | `undefined` | Pins the op to that workspace's owning principal via `workspaceQuery`; omitted falls back to the caller's ownership reach |
| `opts.includeUntriaged` (`projectWorkItemsApi.listForProject`) | `boolean \| undefined` | `false` | Include cards still sitting in the triage inbox in the board's own list |
| `opts.direction` (`projectArtifactsApi.list`) | `"ingested" \| "produced" \| undefined` | `undefined` (both) | Narrow the link list to one side |
| `opts.limit`/`opts.query`/`opts.kind` (`projectArtifactsApi.attachable`) | `number \| string \| string \| undefined` | all `undefined` | Narrow the attachable picker; `limit` is per-kind |
| `opts.workspace`/`opts.limit` (`projectSearchApi.workItems`) | `string \| number \| undefined` | `undefined` / server default `20` | Narrow the search reach and clamp the page size (server clamps 1–50) |
| `opts.workspace`/`opts.limit` (`projectTriageApi.list`) | `string \| number \| undefined` | `undefined` / server default `50` | Narrow the cross-board inbox reach and clamp the page size (server clamps 1–200) |
| `opts.limit` (`projectActivityApi`, keyset) | `number \| undefined` | `undefined` (no page limit, no `nextBefore`) | Page size for the newest-first activity keyset |
| `opts.before` (`projectActivityApi`, keyset) | `string \| undefined` | `undefined` | Opaque `"<createdAt>\|<id>"` composite cursor for the next older page |
| `POLL_INTERVAL_MS` (`live.ts`) | internal constant | `60_000` | Poll cadence while SSE is unavailable for `subscribeToProject` |
| `COALESCE_MS` (`live.ts`) | internal constant | `150` | Trailing coalescing window folding a burst of wakes into one |
| `KEY_PREFIX_REGEX` (`projects.ts`) | `RegExp` constant | `/^[A-Z][A-Z0-9]{1,7}$/` | Client-side mirror of the backend's work-item key-prefix shape rule |
| `WORK_ITEM_PRIORITY_MIN`/`MAX` (`wire.ts`) | `number` constants | `0` / `4` | Bounds `WorkItem.priority` is written and read within under the `"standard"` `PriorityScale` |

## Localization

- **Hardcoded English strings**: `validateKeyPrefix`'s two messages —
  `"A key prefix is required."` and `"Use 2-8 characters: a letter, then
  letters or digits."` — and `DEFAULT_ITEM_NOUN`/`DEFAULT_ITEM_NOUN_PLURAL`
  (`"work item"`/`"work items"`) are fixed English literals in
  `projects.ts`.

No file in this domain defines an i18n key, a lookup table, or a locale
parameter — every user-facing string above is plain, fixed English. This is
a plain, honestly-reported fact about the current source, not a hidden gap
(see Compliance).

## Privacy

- **Data collected**: Board/work-item/plan administrative metadata — names,
  descriptions, statuses, dates, labels, health reports, comment bodies, and
  the `(kind, id)` participant/assignee/author references this domain
  carries but does not itself resolve to a person's profile. `authorLabel`
  on a comment ("how the author was named at the time of writing") and
  `createdBy` on a status update are the closest this domain comes to
  personal data, and both are opaque display strings the backend supplies,
  never computed or enriched here.
- **Storage**: This client holds no cache of its own — every call is a live
  round trip through `authedJson`/`authedRequest`. Whatever caching a
  consumer layers on top (a react-query client, as the sibling
  `hub-domain-ecosystems` recipe's web side documents) is outside this
  domain's files.
- **Transmission**: Every call travels through `authedJson`/`authedRequest`
  (`http.ts`, re-exporting `@agentic-toolkit/auth/client`'s Bearer-token
  client); this domain itself attaches no credentials and reads no cookies.
- **Retention**: This domain retains nothing between calls; it is a stateless
  set of functions over the network. `subscribeToProject`'s module-scope
  `live` map is the one exception — a connection/listener-set entry per
  actively-watched `projectId`, which is discarded the moment the last
  subscriber unsubscribes (`live.ts`), holding no data, only a handle and
  callbacks.

## Platform Notes

- **SwiftUI / AppKit / UIKit**: Not applicable — no Swift declaration exists
  in this domain; there is no Apple-side Projects implementation to note
  concurrency behavior for.
- **React/Web**: This is the sole reference implementation. Every client is
  a plain `async` function object over `fetch` (via `authedJson`/
  `authedRequest`); `useProjectLive` is the one React-specific export (a
  `useEffect`/`useRef` hook), and every other export is framework-agnostic
  and usable from a plain script, a test, or a non-React renderer.
- **Windows / WinUI 3**: No WinUI 3 implementation exists in this domain.
  A WinUI 3 port would need to reproduce the module-scope refcounting
  `subscribeToProject` performs with a `Map`/`Set` (`live.ts`) using
  whatever this platform's equivalent of a singleton connection registry is
  (e.g. a static dictionary keyed by `projectId` guarding one
  `Windows.Web.Http`/`HttpClient`-backed SSE-equivalent connection), since
  the "one connection per board, closed only by the last watcher" contract
  (live-one-connection-per-board-refcounted) is a behavioral requirement of
  this domain, not an artifact of the browser `EventSource` API.
- **Android**: No Android implementation exists in this domain. A Kotlin
  port would face the identical refcounting requirement as Windows above,
  and would need `compareRank`'s byte-order comparator (never a locale
  string comparator) to stay compatible with the backend's `COLLATE "C"`
  column (work-item-rank-is-opaque-byte-order).
- **Python**: No Python implementation exists in this domain.

