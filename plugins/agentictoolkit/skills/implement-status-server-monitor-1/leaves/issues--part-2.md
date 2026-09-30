<!-- leaf: implement-status-server-monitor-1/issues--part-2 · source: status-server-monitor-issues.md -->

# Status Server Monitor Issues — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-1/issues--part-2#<slug>`):

- `per-target-write-isolation` MUST
- `write-failure-log-format` MUST
- `counts-reflect-landed-writes-only` MUST
- `updated-requires-shadow-closure-success` MUST
- `resolved-targets-recorded-before-shadow-closure` MUST
- `reapply-is-idempotent` MUST
- `no-injected-clock` MUST

### Fail-Soft Isolation and Reporting

- **per-target-write-isolation**: For both the `live` loop (open/update) and the `stale` loop (resolve), a thrown error from any storage call for one target's iteration MUST be caught within that same iteration's `try/catch` and MUST NOT prevent `applyBoardToLedger` from processing every other target. Per the source comment, an exception escaping this function would propagate past `runMonitorCycle`'s `finally`, skipping `fetchPeers`, `collectTelemetry`, and the maintenance store's retention prune and heartbeat ping (`cycle-runner.ts`) — and retention pruning silently stopping is what previously drove the per-tick cost past the container's CPU quota.
- **write-failure-log-format**: A caught write failure MUST be reported via `logLedgerFailure(target, err)`, which MUST call `console.error` with exactly the message `` `[ledger] write failed for ${target} — skipped, the next cycle re-derives it: ${err instanceof Error ? err.message : String(err)}` ``.
- **counts-reflect-landed-writes-only**: The `opened`, `updated`, and `resolved` counts, and the `resolvedTargets` array, MUST reflect only writes that completed without throwing — a caught failure for a target MUST NOT be counted as `opened`, `updated`, or `resolved`, and MUST NOT add that target to `resolvedTargets`.
- **updated-requires-shadow-closure-success**: `applyBoardToLedger` MUST increment `updated` for a target only after BOTH `updateIssue` and the subsequent `closeShadows(storage, rows)` call for that target complete without throwing — because `updated++` executes after `closeShadows` in source order, a `closeShadows` failure following a successful `updateIssue` MUST cause that target's `updated` count to be omitted and MUST cause `logLedgerFailure` to log for it, even though the canonical row's update already committed to storage.
- **resolved-targets-recorded-before-shadow-closure**: `applyBoardToLedger` MUST push a stale target onto `resolvedTargets` immediately after its canonical row's `resolveIssue` call succeeds and BEFORE calling `closeShadows` for that target. Because that push executes before `closeShadows` in source order, a subsequent `closeShadows` failure for the same target MUST NOT remove it from `resolvedTargets` or from the `resolved` count, even though `logLedgerFailure` still logs a write failure for that target — unlike the `updated` count above, whose accounting is the opposite way around.

### Determinism

- **reapply-is-idempotent**: Invoking `applyBoardToLedger` twice in succession with an unchanged `Board` (the same `problems` and `monitoredTargets`) MUST return `opened: 0` on the second call and MUST leave the ledger's row count unchanged, because the target already has a matching open row that the second call only refreshes.
- **no-injected-clock**: `applyBoardToLedger` and `openByTarget` MUST NOT accept a caller-supplied clock or `nowMs` parameter; every timestamp either function's underlying storage primitives write MUST come from that primitive's own `new Date()` call at the moment it runs. Per the source comment, the rule requiring an injectable clock applies to `deriveBoard`, which must be pure for the regression suite — this function is the opposite kind, one that exists to write rows, and giving it a `nowMs` it cannot hand to any of its three primitives would document a guarantee it does not make.

### Concurrency

- **concurrent-write-ordering**: NEEDS REVIEW: Not implemented in source. `openIssue`'s insert is guarded against a concurrent race by the database's partial unique index via `onConflictDoNothing`, but `updateIssue` and `resolveIssue` carry no equivalent guard — no compare-and-swap, version check, or transaction ties a target's read (via `openByTarget`) to its later write. `board/reconcile.ts`'s own doc comment states that `reconcileBoardLedger` (this function's sole caller) runs from both the monitor's `Worker` thread and several API-thread call sites against the same underlying storage, so two `applyBoardToLedger` invocations racing on the same target's open row are a real possibility, not a hypothetical one. What happens when they do — whether the second write's plain last-write-wins overwrite of the first is acceptable (both are honest projections of the board at each caller's own read time) or needs an optimistic-lock/transaction — is not stated anywhere in this file or its callers. Settled by confirming with the `status-server` maintainers whether `reconcileBoardLedger`'s call sites are expected to genuinely overlap in production traffic.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` (parameter to `openByTarget` and `applyBoardToLedger`) | `Storage` | none — caller-supplied | The persistence port this file writes through; every call in this file reaches storage exclusively via `storage.issues.*`. This file never constructs or configures a `Storage` implementation itself. |
| `board` (parameter to `applyBoardToLedger`) | `Board` | none — caller-supplied | The derived verdict to record — produced by `deriveBoard` from board facts, external to this file, and passed in unchanged by `board/reconcile.ts`'s `reconcileBoardLedger`. |

This file reads no environment variable and defines no module-level constant of its own; every configurable value (the alert webhook URL, retention windows, probe cadence) belongs to `alerts.ts`, `maintenance-store.ts`, or `config/env.ts`, all external to this file.

## Privacy

- **Data collected**: the fields this file reads from a `Problem` and writes to an `IssueRow` — `target`, `source`, `name`, `environment`, `severity`, `state`, `statusCode`, `detail`, `sourceUrl`, `liveUrl`, `commitHash`, `commitMessage`, `commitRepo` — are infrastructure and deploy metadata describing a monitored site's or project's health, sourced from the board's derivation of provider APIs and roster configuration. None of it is entered by an end user of the monitored product, and this file never constructs, reads, or transmits a credential or token.
- **Storage**: persisted durably to the `issues` table through the injected `Storage` port (the libSQL store, external to this file). An open row survives a process restart; a resolved row is retained for 90 days (`ISSUE_RESOLVED_RETENTION_DAYS`, enforced by `maintenance-store.ts`'s retention prune, external to this file) before it is deleted.
- **Transmission**: this file makes no network call itself. Opening a new problem, or resolving one as a genuine recovery, queues an `IssueAlert` via `notifyIssueAlert` (`alerts.ts`) that a later, separately-invoked `flushAlerts` call may transmit off-box to an operator-configured webhook — this file only decides whether to queue an alert, never sends one.
- **Retention**: an open row has no expiry and persists until this module resolves it; a resolved row is retained for 90 days before the external retention prune deletes it. This file implements neither the prune nor any backup mechanism for the `issues` table.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend or service embedding this ledger pattern would model `OpenInput` and `IssueRow` as `Sendable` structs, express the `Storage.issues` port as a protocol with an `actor`-isolated conformer over its SQLite/libSQL-backed store, and give `applyBoardToLedger` the same per-target isolation using a Swift `do { ... } catch { logLedgerFailure(target, error) }` inside a `for` loop over the board's problems, `await`-ing each storage call in turn.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin/JVM port models `OpenInput`/`IssueRow` as `data class`es, `Storage.issues` as an interface backed by a suspendable store (Room/SQLDelight or Exposed), reuses `groupBy` for `openByTarget`'s target-keyed grouping, and makes `applyBoardToLedger` a `suspend fun` whose per-target `try { ... } catch (e: Exception) { logLedgerFailure(target, e) }` inside a `for` loop preserves the same fail-soft isolation across coroutine calls.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/issues.ts` as a set of exported and private `async` functions with no class and no framework dependency of its own. It is called exclusively through `board/reconcile.ts`'s `reconcileBoardLedger`, which in turn runs from the monitor's `Worker` cycle (`cycle-runner.ts`) and from several API-thread routes and MCP tools. It depends on `Storage.issues` (`storage/ports.ts`, implemented in `libsql/stores/issue-store.ts`) and on `notifyIssueAlert` (`alerts.ts`).
- **AppKit / UIKit**: same non-UI framing as SwiftUI. This file holds no in-memory state between calls of its own — unlike the sibling alerts recipe's module-level queue, which is per-`Worker`-thread in Node — so a Swift service embedding this pattern needs no analogue to that per-thread isolation concern; every call to `applyBoardToLedger` is a self-contained read-then-write against the shared database.
- **WinUI 3**: a .NET port models `OpenInput` as a `record` with the same fields (`CommitHash`/`CommitMessage`/`CommitRepo` as nullable `string?` properties, defaulted to `null` in a constructor or `with`-expression rather than left unset), `IssueRow` as a `record` returned by a `Task<IReadOnlyList<IssueRow>> ListOpenAsync()` method on an `IIssueStore` interface (the `Storage.issues` port's analogue), and `ApplyBoardToLedgerAsync(IStorage storage, Board board)` as an `async Task<LedgerCounts>` that loops `board.Problems` with `try { ... } catch (Exception ex) { LogLedgerFailure(target, ex); }` per target — mirroring the fail-soft isolation exactly. The `uniq_open_issue_per_target` partial unique index's `ON CONFLICT DO NOTHING` guard needs an explicit unique index plus a caught `DbUpdateException` (EF Core) or `SqliteException` to reproduce with `System.Text.Json`/ADO.NET, since neither has a direct equivalent to Drizzle's `onConflictDoNothing`.

