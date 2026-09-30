<!-- leaf: implement-hub-domain-2/projects--test-vectors · source: hub-domain-projects.md -->

# Hub Domain: Projects

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-projects-001 | project-list-sorted-by-name | `projectsApi.list()` over rows named `["Beta","Alpha"]` | Result names `["Alpha","Beta"]` (`"list GETs the base URL and sorts by name"`, `projects.test.ts`) |
| hub-domain-projects-002 | project-participant-remove-addressing | `participants.remove("p1","cust1","customer")` | `DELETE /api/project/projects/p1/participants/cust1?kind=customer` (`projects.test.ts`) |
| hub-domain-projects-004 | project-update-preserves-explicit-null | `update("1", {name:"Renamed", description: undefined, archivedAt: null})` | Body `{"name":"Renamed","archivedAt":null}` — `description` dropped, `archivedAt` kept (`"dropping undefined but KEEPING explicit null"`, `projects.test.ts`) |
| hub-domain-projects-006 | project-key-prefix-shape | `validateKeyPrefix("AB")`, `"WEB"`, `"ADH2"`, `"A1B2C3D4"` | All `null` (`"accepts 2-8 characters starting with a letter"`, `projects.test.ts`) |
| hub-domain-projects-007 | project-key-prefix-shape, project-key-prefix-empty-refused-not-cleared | `validateKeyPrefix("")`, `"   "` | Both match `/required/i` (`projects.test.ts`) |
| hub-domain-projects-008 | project-key-prefix-shape | `validateKeyPrefix("A")`, `"ABCDEFGHI"`, `"1AB"`, `"A-B"`, `"A B"`, `"AB!"` | All non-null (`"refuses a single character, a 9th character, a leading digit, and punctuation"`, `projects.test.ts`) |
| hub-domain-projects-010 | work-item-rank-is-opaque-byte-order | `compareRank("aZ","az")` vs `"aZ".localeCompare("az")` | `compareRank < 0`; `localeCompare > 0` (`"sorts by BYTES, so a capital letter sorts before every lower-case one"`, `projects.test.ts`) |
| hub-domain-projects-011 | work-item-rank-is-opaque-byte-order | `["V1","V0","V0V","V2"].sort(compareRank)` | `["V0","V0V","V1","V2"]` (`"orders the keys the backend actually mints"`, `projects.test.ts`) |
| hub-domain-projects-012 | work-item-update-clears-via-explicit-null | `update("w1", {assigneeKind:null, assigneeId:null, dueDate:null, parentId:null, title:undefined})` | Body `{"assigneeKind":null,"assigneeId":null,"dueDate":null,"parentId":null}` (`projects.test.ts`) |
| hub-domain-projects-013 | work-item-move-null-survives-compact | `move("w1", {afterId:null, beforeId:undefined})` | Body `{"afterId":null}` (`"to an END sends an explicit null rather than stripping it"`, `projects.test.ts`) |
| hub-domain-projects-014 | work-item-key-derivation | `projectsApi.get` on a row with no `keyPrefix` | `p.keyPrefix === ""` (`projects.test.ts`) |
| hub-domain-projects-015 | work-item-key-derivation | `listForProject` on a row with `itemKey: "WEB-42"` | `w.itemKey === "WEB-42"` (`projects.test.ts`) |
| hub-domain-projects-018 | search-blank-query-short-circuits | `projectSearchApi.workItems("")` and `workItems("   ")` | Both resolve to `EMPTY_WORK_ITEM_SEARCH`; `authedJson` never called (`search.test.ts`) |
| hub-domain-projects-019 | search-query-trimmed-before-send | `workItems("  tungsten  ")` | Request URL `?q=tungsten` (`search.test.ts`) |
| hub-domain-projects-020 | search-optional-params-omitted-when-unset | `workItems("tungsten", {workspace:"acme", limit:5})` vs `workItems("tungsten")` | First: `?q=tungsten&workspace=acme&limit=5`; second: `?q=tungsten` alone (`search.test.ts`) |
| hub-domain-projects-021 | search-result-order-is-servers, search-echoed-limit-may-differ-from-requested | Server returns `[weaker(rank 0.1), hitRow(rank 0.6)]` with `limit:50, hasMore:true` for a request of `limit:500` | `result.results` ids `["w2","w1"]` (server order kept); `result.limit === 50` (`"keeps the server's order and reports the limit the server ACTUALLY applied"`, `search.test.ts`) |
| hub-domain-projects-022 | search-hit-defaults-snippet-and-rank | `toWorkItemSearchHit({...hitRow(), snippet:undefined, rank:undefined})` | `hit.snippet === ""`, `hit.rank === 0` (`search.test.ts`) |
| hub-domain-projects-023 | activity-before-token-is-opaque-composite, activity-next-before-full-page-heuristic | `projectActivity("p1", {limit:2, before:"2026-01-02T00:00:00.000Z"})` returning 2 rows (a1@t1, a2@t2) | Query `?limit=2&before=2026-01-02T00%3A00%3A00.000Z`; `page.nextBefore === "t2|a2"` (`live.test.ts` sibling `projects.test.ts`) |
| hub-domain-projects-024 | activity-before-token-is-opaque-composite | `projectActivity("p1", {limit:2, before:"t2|a2"})` | Query `?limit=2&before=t2&beforeId=a2` (`projects.test.ts`) |
| hub-domain-projects-025 | comment-list-oldest-first, comment-add-omits-parent-id-for-top-level | `list("w1")` over `[c1,c2]`; `add("w1","hello")` | `out` ids `["c1","c2"]`; add body `{"body":"hello"}` (no `parentId` key) (`projects.test.ts`) |
| hub-domain-projects-026 | comment-threading-one-level-deep | `threadOf([c1, c2(parent c1), c3, c4(parent c1)])` | Roots `["c1","c3"]`; `c1`'s replies `["c2","c4"]` (`projects.test.ts`) |
| hub-domain-projects-027 | comment-orphan-promoted-not-dropped | `threadOf([c1, orphan(parent "gone")])` | Roots `["c1","orphan"]` — orphan promoted, not dropped (`"promotes a reply whose parent is missing instead of dropping it"`, `projects.test.ts`) |
| hub-domain-projects-028 | comment-author-kind-unknown-falls-back-to-customer | `list("w1")` on a row with `authorKind:"martian"` | `c.authorKind === "customer"` (`projects.test.ts`) |
| hub-domain-projects-029 | artifact-link-id-distinct-from-target-id, artifact-unresolvable-target-kept-as-null, artifact-list-server-order-preserved | `list("p1")` over `[a2, a1]`, then over `[{...a1, target:null}]` | ids stay `["a2","a1"]` (not re-sorted); the null-target row keeps `targetKind:"content.markdown"`, `targetId:"d1"`, `target:null` (`projects.test.ts`) |
| hub-domain-projects-030 | artifact-unlink-addresses-link-not-target | `unlink("p/1","a/1")` | `DELETE /api/project/projects/p%2F1/artifacts/a%2F1` (`projects.test.ts`) |
| hub-domain-projects-031 | live-one-connection-per-board-refcounted | Three `subscribeToProject("p1", ...)` calls | Exactly one `connectSse` open (`"opens ONE stream for a board however many panes are watching it"`, `live.test.ts`) |
| hub-domain-projects-033 | live-one-connection-per-board-refcounted | Two subscribers on `"p1"`; unsubscribe one, then the other | `close` not called after the first unsubscribe; called once after the second (`"closes only when the LAST watcher goes away"`, `live.test.ts`) |
| hub-domain-projects-034 | live-reopens-after-going-quiet | Subscribe+unsubscribe `"p1"` (closes), then subscribe `"p1"` again | A second, distinct `connectSse` call is made (`live.test.ts`) |
| hub-domain-projects-035 | live-coalesces-burst-into-one-wake | Three `serverSaysChanged()` calls then `vi.runAllTimers()` | `onWake` called exactly once (`"folds a BURST of changes into a single refetch"`, `live.test.ts`) |
| hub-domain-projects-036 | live-wakes-again-after-window-closes | `serverSaysChanged()` + run timers, then again | `onWake` called twice total (`live.test.ts`) |
| hub-domain-projects-037 | live-poll-fallback-wakes-identically | `opened[0].onPoll()` then run timers | `onWake` called once (`"wakes on the poll fallback exactly as it does on a live event"`, `live.test.ts`) |
| hub-domain-projects-038 | live-unsubscribe-during-pending-wake-is-silent | Two subscribers; one calls `serverSaysChanged()` then unsubscribes before timers run | The unsubscribed watcher is never called; the staying one is called once (`live.test.ts`) |
| hub-domain-projects-039 | live-last-unsubscribe-drops-pending-timer | Single subscriber triggers a wake, then unsubscribes before timers run | `onWake` never called; `close` called once (`"drops a pending wake when the last watcher leaves"`, `live.test.ts`) |
