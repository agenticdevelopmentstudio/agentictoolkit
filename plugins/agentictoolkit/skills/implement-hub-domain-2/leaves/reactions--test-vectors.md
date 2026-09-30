<!-- leaf: implement-hub-domain-2/reactions--test-vectors · source: hub-domain-reactions.md -->

# Hub Domain: Reactions

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| reactions-001 | wire-types-own-transcription | Read the import statement at the top of `reactions.ts` | Imports `ReactionCreateBody`/`ReactionRow` only from `./wire`; no import from `@agentic-toolkit/adh-api-types` |
| reactions-002 | api-proxy-path-prefix, path-segment-encoding | `reactionsApi.list("project.comments", ["c1", "c2"])` | `authedJson` called once with `"/api/content/reactions?targetKind=project.comments&targetIds=c1%2Cc2"` (per `reactions.test.ts`, "reads MANY subjects in one request") |
| reactions-003 | list-empty-input-short-circuits | `reactionsApi.list("project.comments", [])` | Resolves to `[]`; `authedJson` is never called (per `reactions.test.ts`, "issues NO request for an empty subject list") |
| reactions-004 | list-deduplicates-target-ids | `reactionsApi.list("project.comments", ["c1", "c1", "c2"])` | `authedJson` called with `targetIds=c1%2Cc2` — `"c1"` appears once (per `reactions.test.ts`, "de-duplicates subjects before asking") |
| reactions-005 | list-target-id-cap, list-chunks-issued-concurrently | `reactionsApi.list("project.comments", <201 distinct ids>)` | `authedJson` called exactly twice; the first call's `targetIds` has 200 entries, the second has 1 (per `reactions.test.ts`, "chunks past the backend's cap") |
| reactions-006 | list-merges-chunks-in-order | Same 201-id call, with the two chunk responses mocked to resolve `{items:[row("r1")]}` then `{items:[row("r2")]}` | Resolved array is `[r1, r2]`, in that order (per `reactions.test.ts`, "merges every chunk's rows into one list") |
| reactions-007 | add-idempotent-on-repeat | `reactionsApi.add("project.comments", "c1", "👍")` with `authedJson` mocked to resolve a `ReactionRow` | POST to `/api/content/reactions` with body `{"targetKind":"project.comments","targetId":"c1","emoji":"👍"}`; resolves with the mapped `Reaction` (per `reactions.test.ts`, "add POSTs the whole subject") |
| reactions-008 | remove-addressed-by-reaction-id | `reactionsApi.remove("r1")` | `authedRequest` called with `"/api/content/reactions/r1"` and `{ method: "DELETE" }` (per `reactions.test.ts`, "remove addresses the REACTION's id") |
| reactions-009 | tally-counts-per-emoji, tally-mine-identifies-viewers-own-reaction | `tally([r1(👍,cust-1), r2(👍,cust-2), r3(🎉,cust-2)], "cust-1")` | `[{emoji:"👍",count:2,mine:"r1"},{emoji:"🎉",count:1,mine:null}]` (per `reactions.test.ts`, "counts per emoji and hands back the VIEWER's own reaction id") |
| reactions-010 | tally-null-viewer-honest-rendering | `tally([r1(👍), r2(🎉)], null)` | Every returned `ReactionTally.mine` is `null` (per `reactions.test.ts`, "claims nothing when the viewer is unknown") |
| reactions-011 | tally-sort-order | `tally([r1(🎉), r2(👍), r3(👀), r4(👀)], null)` | Emoji order `["👀","🎉","👍"]` — 👀 first on count (2), then 🎉 before 👍 on first-appearance (per `reactions.test.ts`, "orders by count, and a tie keeps the order the emoji first appeared") |
| reactions-012 | by-target-groups-preserving-order, by-target-omits-empty-targets | `byTarget([r1(c1), r2(c2), r3(c1)])`, then read `.get("c9")` | Keys in order `["c1","c2"]`; `groups.get("c1")` is `[r1,r3]`; `groups.get("c9")` is `undefined` (per `reactions.test.ts`, "unpacks a batched read back into one bucket per subject") |
| reactions-013 | to-reaction-field-projection | `toReaction({id:"r1",customerId:"cust-1",ecosystemId:"eco-1",targetKind:"project.comments",targetId:"c1",emoji:"👍",createdAt:"t-r1",deletedAt:null})` | Returned `Reaction` has exactly `{id,customerId,targetKind,targetId,emoji,createdAt}`; no `ecosystemId` or `deletedAt` key present |
| reactions-014 | error-propagation-unmodified | `authedJson` mocked to reject with an `AuthHttpError(503, "no worker registered")` for `reactionsApi.add` | The returned promise rejects with that same error, unmodified |
| reactions-015 | list-scope-is-ecosystem-public | Read `reactionsApi.list`'s implementation | No filter, `.filter`, or comparison against a caller/actor id anywhere in the method body |
