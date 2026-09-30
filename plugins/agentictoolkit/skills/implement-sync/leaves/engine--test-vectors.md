<!-- leaf: implement-sync/engine--test-vectors · source: sync-engine.md -->

# SyncEngine

## Conformance Test Vectors

All engine vectors use `SyncEngineConfiguration(deviceId: "test-device", pullLimit: 10, pushBatchSize: 5, …)`, a scripted transport and an in-memory store, as `SyncEngineTests` does.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sync-engine-001 | pull-request, pull-continues, apply-advances | Pages `a` (cursor c1, hasMore true) then `b` (cursor c2, hasMore false); `syncNow(.manual)` | Cursors sent are nil then c1; stored cursor is c2; 2 mirror rows |
| sync-engine-002 | conflict-adopt, strip-bookkeeping, adopt-before-complete | Staged upsert r1; push returns `.conflict` with `current` title "theirs", `sync_version` 9, `sync_stamped_at`, `deleted_at` null | Outbox empty; mirror r1 title "theirs", syncVersion "9"; no `sync_version`/`sync_stamped_at` in its data |
| sync-engine-003 | delete-wins | Same as 002 but `deleted_at` is a timestamp | Outbox empty; r1 tombstoned with syncVersion "9" and empty data; live row count 0 |
| sync-engine-004 | conflict-no-current | `.conflict` with `current` nil, reason "server_row_missing" | Outbox empty; op in quarantine; local title still "mine" |
| sync-engine-005 | conflict-unadoptable, adopted-version | `.conflict` with `sync_version` `.number(.infinity)` | Op quarantined; outbox empty; local row untouched |
| sync-engine-006 | conflict-unadoptable, pushed-event, cycle-success | Two ops: "bad" conflict with `sync_version` "not-a-number", "good" `.applied` newVersion "7" | Outbox empty; only "bad" quarantined; events contain `.idle`, no `.failed` |
| sync-engine-007 | unauthorized-pause, syncnow-auth-gate | First pull throws `.unauthorized`; then `syncNow(.periodic)`; then `syncNow(.manual)` | 1 pull after the periodic call; 2 pulls after the manual call |
| sync-engine-008 | resync-required, resync-preserves-outbox | Stored row "old" at cursor "stale", one staged op; pull throws `.resyncRequired`, then returns row "fresh" | "fresh" present, "old" gone; the staged opId pushed exactly once; outbox empty |
| sync-engine-009 | resync-unauthorized | Pulls: `.resyncRequired`, then `.unauthorized`; then `syncNow(.periodic)` | 2 pulls total; events include `.resyncPerformed` and `.authRequired`, no `.failed` |
| sync-engine-010 | resync-nested-once, resync-counter-persists | Transport always throws `.resyncRequired`; `syncNow(.manual)` three times | Pull count 3, then 5, then 7; 3 `.failed` events each containing "resync_required"; outbox still 1 op |
| sync-engine-011 | generic-failure | Push throws `.transport("boom")` | Outbox still holds 1 op |
| sync-engine-012 | backoff-delay, cycle-success | Pulls fail 3 times, succeed, fail once, succeed; baseBackoff 0.02 | Retries fire unaided; the post-success retry gap is under 3x the first retry gap; 4 `.failed` events |
| sync-engine-013 | push-no-progress | Push result opId "bogus-op-id-not-in-outbox" `.applied` | Outbox still 1 op; a `.failed` event emitted |
| sync-engine-014 | push-no-progress, engine-error-text | Non-empty batch answered with `results: []` | No `.idle`; first `.failed` payload is "push made no progress"; outbox 1 op |
| sync-engine-015 | rejected-result, store-complete-terminal | Push result `.rejected` reason "invalid_data"; then a second `syncNow` | Op quarantined; outbox empty; exactly 1 push request across both cycles |
| sync-engine-016 | pull-no-progress | Four pages all empty, cursor "stalled", hasMore true | Exactly 3 pulls; first `.failed` payload is "pull made no progress" |
| sync-engine-017 | pause-wait | `pause()` called while a gated pull is in flight | `pause()` has not returned before release; returns after the cycle ends |
| sync-engine-018 | syncnow-join, follow-up-cycle | Two concurrent `syncNow` calls (manual, periodic) against a gated pull | Neither returns before release; both return after; exactly 2 pulls |
| sync-engine-019 | kick-paused, syncnow-paused, pause-drops-pending | `pause()` while idle, then `kick(.periodic)` and `syncNow(.manual)` | 0 pulls |
| sync-engine-020 | resume-no-sync, kick-start | `pause()`, `kick(.periodic)`, `resume()`, `kick(.manual)` | Exactly 1 pull |
| sync-engine-021 | reconcile-resync, resync-preserves-outbox | Registered a.x at cursor c1; staged op on a.x; next manifest [a.x, b.y] | `.resourcesEnabled(["b.y"])` and `.resyncPerformed`; 3rd pull cursor nil; staged op still pending; b.y has 1 row; cursor c3 |
| sync-engine-022 | disable-purge, manifest-complete | Registered a.x and b.y; staged op on b.y; next manifest [a.x] | `.resourcesDisabled(["b.y"])`, no `.resyncPerformed`; a.x keeps 1 row; b.y unregistered; op quarantined; cursor c2 |
| sync-engine-023 | bump-purge, reconcile-resync | a.x registered at 1; manifest reports 2 | `.resourcesSchemaBumped(["a.x"])`, `.resyncPerformed`; 3rd pull cursor nil; registration a.x = 2 |
| sync-engine-024 | bump-purge, reconcile-plan | a.x registered at 2; manifest reports 1 | Same bump path; registration a.x = 1; old row "1" gone, new row "2" present |
| sync-engine-025 | effective-set, change-filter, unregistered-event | hostResources [a.x]; manifest [a.x, b.y] with a change for each | `.unregisteredManifestResources(["b.y"])`; a.x 1 row; registrations exactly a.x = 1 |
| sync-engine-026 | unregistered-event | hostResources [a.x]; 3 pages each with manifest [a.x, b.y] | 3 pulls; exactly one `.unregisteredManifestResources(["b.y"])` |
| sync-engine-027 | fresh-cursor-no-resync | Fresh store; manifest [a.x, b.y] | No `.resourcesEnabled`, no `.resyncPerformed`; one `.pulledBatch` |
| sync-engine-028 | reconcile-bound | Alternating pages manifest [a.x] then [a.x, b.y], four times | 8 pulls; `.failed` payloads exactly ["manifest unstable"] |
| sync-engine-029 | reconcile-plan | registered {a.x:1, b.y:1}, effective [a.x@1] | disabled ["b.y"], bumped [], appeared [] |
| sync-engine-030 | reconcile-plan | registered {a.x:1}, effective [a.x@2, b.y@1] | bumped ["a.x"], appeared ["b.y"], disjoint |
| sync-engine-031 | reconcile-plan | registered {a.x:1, b.y:1, c.z:3}, effective [] | disabled ["a.x", "b.y", "c.z"], others empty |
| sync-engine-032 | reached-backend | Each `SyncEvent` case | true for `.idle`, `.pulledBatch`, `.authRequired`; false for the other nine |
| sync-engine-033 | uuidv7-format, uuidv7-monotonic | 1000 back-to-back `SyncID.uuidV7()` calls | Strictly increasing, no duplicates, 36 characters, character 14 is "7" |
| sync-engine-034 | catalog-shape | `ADHSyncCatalog` | 97 unique names, 44 pull-only, all schemaVersion 1; "social.follows" pull-only, "content.contacts" not |

**stop-during-cycle** and **adopted-version-sign** have no vector: the first is the open question on stop-during-cycle, and the second's intended behavior is the open question on adopted-version-sign.
