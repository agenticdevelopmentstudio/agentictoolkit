<!-- leaf: implement-general-1/adh-offline-sync-client--logging · source: adh-offline-sync-client.md -->

# ADH Offline Sync Client

## Logging

The engine emits a `SyncEvent` stream (`SyncEngine.events`,
`.bufferingNewest(256)`); hosts drain it to drive status UI. The full enum
(`SyncEvents.swift`):

| Event | Payload | Meaning |
|---|---|---|
| `started` | `SyncKickReason` | A cycle began (`.periodic` / `.connectivityRestored` / `.manual` / `.hostSpecific`). |
| `pulledBatch` | `changes: Int, cursor: SyncCursor` | One pull page applied atomically; cursor advanced. |
| `pushed` | `applied: Int, conflicts: Int, rejected: Int` | One push round-trip resolved. |
| `conflictResolved` | `resource: String, rowId: String` | A conflict adopted the server row locally. |
| `resyncPerformed` | — | Mirror + cursor reset and a full re-pull ran. |
| `resourcesEnabled` | `[String]` | **New:** resources newly in the effective set on a non-fresh cursor (a full resync was performed). |
| `resourcesDisabled` | `[String]` | **New:** resources that left the effective set — mirror purged, outbox quarantined, registration removed. |
| `resourcesSchemaBumped` | `[String]` | **New:** registered resources whose manifest schemaVersion rose — purged + resynced. |
| `unregisteredManifestResources` | `[String]` | **New:** manifest resources the host did not register — ignored, surfaced for observability. |
| `authRequired` | — | 401: engine paused, awaiting a manual kick. |
| `failed` | `String` | Human-readable failure; ops remain queued and a backoff retry is scheduled. |
| `idle` | — | A full pull + push cycle completed with no error. |

**`reachedBackend` classification** (`SyncEvent.reachedBackend`): a *reachability*
signal, not sync-health. `true` for `pulledBatch`, `idle`, and `authRequired`
(the backend answered — even a 401 is proof of a live round trip). `false` for
`started`, `pushed`, `conflictResolved`, `resyncPerformed`, `resourcesEnabled`,
`resourcesDisabled`, `resourcesSchemaBumped`, `unregisteredManifestResources`,
and `failed` (which covers both "never reached the backend" and "the backend
errored"). The switch is exhaustive on purpose so a new event forces a decision
at this call site.
