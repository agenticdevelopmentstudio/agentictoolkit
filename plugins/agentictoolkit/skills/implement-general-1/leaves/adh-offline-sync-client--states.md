<!-- leaf: implement-general-1/adh-offline-sync-client--states · source: adh-offline-sync-client.md -->

# ADH Offline Sync Client

## States

The engine runs one cycle at a time; a coalesced kick runs a follow-up cycle
after the current one returns. `SyncEngine` is an actor, so these are logical
phases of a single cycle, not concurrent states.

| State | Entry condition |
|---|---|
| Idle | No cycle running. Emitted (`.idle`) after a full pull + push cycle completes with no error, and the resting state between cycles. |
| Pulling | A kick (`.periodic`/`.connectivityRestored`/`.manual`/`.hostSpecific`) started a cycle; `pullLoop` reads the stored cursor and fetches a page. Loops while `hasMore`, applying each batch atomically before the next request. |
| Reconciling | Every pull iteration, before `apply`: the effective manifest is diffed against the store's registrations — disappearances purge, schema bumps purge, appearances/bumps on a non-fresh cursor reset the mirror. |
| Resyncing | A reconcile reset fired (appearance/schema-bump on a non-fresh cursor), or the server returned 410 (`resyncRequired`): mirror + cursor cleared, outbox preserved, full re-pull from a nil cursor (`.resyncPerformed`). |
| Pushing | `pullLoop` finished; `pushLoop` drains the outbox in `pushBatchSize` batches, resolving each result (applied/conflict/rejected) and looping until the outbox is empty. |
| AuthRequired | The transport returned 401 (`unauthorized`); the engine pauses (`.authRequired`) and only a manual kick resumes it. |
| Backing-off | A transport/5xx failure, a bounded-guard trip (`pushMadeNoProgress`, `pullMadeNoProgress`, `manifestUnstable`), or a repeated 410 scheduled an exponential-backoff retry (`.failed`, then a `.periodic` kick after `min(baseBackoff · 2^(n−1), maxBackoff)` for the n-th consecutive failure). |
