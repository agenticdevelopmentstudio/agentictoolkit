<!-- leaf: implement-general-1/adh-offline-sync-client--test-vectors · source: adh-offline-sync-client.md -->

# ADH Offline Sync Client

## Conformance Test Vectors

One row per Behavioral Requirement. Tests live in the two XCTest bundles
(`AgenticToolkitSyncTests`, `AgenticToolkitSyncGRDBTests`); wire-shape rows also
cite `SyncWireTests` and the vendored fixtures under `Tests/…/Fixtures`.

| ID | Requirements | Input | Expected |
|---|---|---|---|
| R1 | effective-set-is-intersection | `hostResources = [a.x]`; manifest = `[a.x, b.y]` with changes for both | Only `a.x` changes applied; `b.y` skipped — `SyncEngineTests.testHostSubsetFiltersManifestAndChanges` |
| R2 | unregistered-resources-surfaced | Manifest carries `b.y` the host did not register | `b.y` ignored; `.unregisteredManifestResources(["b.y"])` emitted — `SyncEngineTests.testHostSubsetFiltersManifestAndChanges` |
| R3 | appearance-forces-full-resync | `b.y` enters the effective set on a non-fresh cursor | Mirror + cursor reset, full re-pull, `.resourcesEnabled(["b.y"])` + `.resyncPerformed` — `SyncEngineTests.testAppearanceOnNonFreshCursorTriggersFullResync` |
| R4 | resync-preserves-outbox | A staged op exists when a 410 forces resync | Op replayed under its original opId after the re-pull — `SyncEngineTests.testResyncRequiredResetsMirrorPreservingOutboxThenRepullsAndReplaysOutbox` |
| R5 | disappearance-purges-mirror | `b.y` leaves the effective set | Its mirror rows deleted, registration removed, cursor untouched, `.resourcesDisabled(["b.y"])` — `SyncEngineTests.testDisappearancePurgesQuarantinesAndKeepsCursor` |
| R6 | disappearance-quarantines-outbox | Pending op for the departing `b.y` | Op moved to quarantine, never pushed — `SyncEngineTests.testDisappearancePurgesQuarantinesAndKeepsCursor`; store: `InMemorySyncStoreTests.testPurgeResourcesDropsRowsQuarantinesOpsDeregisters` / `GRDBSyncStoreTests.testRegistrationsAndPurgeResources` |
| R7 | schema-bump-is-disappear-then-appear | `a.x` manifest schemaVersion CHANGES from the registered version — a rise (v1→v2) or a fall (v2→v1) | Purged then resynced, `.resourcesSchemaBumped(["a.x"])` — `SyncEngineTests.testSchemaBumpPurgesAndResyncs` (rise) and `SyncEngineTests.testSchemaDowngradePurgesAndResyncs` (fall); pure classification: `SyncEngineTests.testReconcilePlanClassifiesVersionRiseAsBumped` / `testReconcilePlanClassifiesVersionFallAsBumped` |
| R8 | cursor-is-opaque | Pull response whose cursor is an opaque base64 string; apply throws mid-batch | Cursor persisted only with a fully applied batch; never parsed — `GRDBSyncStoreTests.testApplyIsAtomicWithCursor`; wire: `SyncWireTests.testDecodesPullResponseFixture` (`Fixtures/pull-response.json`) |
| R9 | tombstones-apply-as-deletes | Pulled change `{op: delete}` with no data | Row soft-deleted locally (drops out of live rows) — `GRDBSyncStoreTests.testDeleteTombstonesLocallyAndResyncPreservesOutbox`; wire: `SyncWireTests.testDecodesPullResponseFixture` (delete row, `Fixtures/pull-response.json`) |
| R10 | pull-drains-has-more | Two pages, first with `hasMore = true` | Both pages pulled and applied atomically, cursor advanced per batch — `SyncEngineTests.testPullLoopsWhileHasMoreAndAdvancesCursorPerBatch` |
| R11 | pull-only-refused-at-stage | `stage` a mutation for a resource in `pullOnlyResources` | Throws `SyncStoreFailure.pullOnlyResource`, no outbox op — `InMemorySyncStoreTests.testStageRefusesPullOnlyResource`, `GRDBSyncStoreTests.testStageRefusesPullOnlyResource` |
| R12 | rejected-is-terminal | Push result `{status: rejected}` | Op quarantined, absent from the next cycle's push — `SyncEngineTests.testRejectedPushResultQuarantinesOpAndIsNotRetriedNextCycle`; store: `GRDBSyncStoreTests.testCompleteAppliedRemovesOpRejectedQuarantines` |
| R13 | conflict-adopts-server-row | Push result `{status: conflict, current}` with server `sync_version` | Server row adopted locally, `sync_version` preserved, bookkeeping cols stripped — `SyncEngineTests.testPushDrainsOutboxAndAppliesConflictCurrentLocally`; delete wins when `current.deleted_at` is set (adopted as a local delete, mirror row tombstoned) — `SyncEngineTests.testPushConflictWithDeletedCurrentAppliesAsLocalDelete` |
| R14 | applied-adopts-new-version | Push result `{status: applied, newVersion}` | Mirror row's base version updated before the outbox row is cleared — `InMemorySyncStoreTests.testCompleteAppliedAdoptsNewVersionOntoMirrorRowForSubsequentStage`, `GRDBSyncStoreTests.testCompleteAppliedAdoptsNewVersionOntoMirrorRowForSubsequentStage`; wire: `SyncWireTests.testDecodesPushResponseFixtureIncludingConflictRow` (`Fixtures/push-response.json`) |
| R15 | identity-change-purges | Identity change with mirror rows, cursor, pending/inflight/quarantined ops | Mirror + cursor + entire outbox cleared, registrations kept — `GRDBSyncStoreTests.testPurgeForIdentityChangeClearsMirrorsCursorAndOutboxButKeepsRegistrations` |
| R16 | recovery-never-deletes-database | Resync and identity-change purge on a live on-disk store | Only rows deleted; the store keeps serving afterward (file survives) — `GRDBSyncStoreTests.testPurgeForIdentityChangeClearsMirrorsCursorAndOutboxButKeepsRegistrations`, `GRDBSyncStoreTests.testDeleteTombstonesLocallyAndResyncPreservesOutbox` |
| R17 | catalog-is-not-authority | Catalog lists a resource the manifest omits (or vice versa) | Manifest gates what actually syncs; catalog only shapes registration/refusal — `ADHSyncCatalogTests.testCatalogShape`, `SyncEngineTests.testHostSubsetFiltersManifestAndChanges` |
