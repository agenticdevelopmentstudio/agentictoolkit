---
id: 130fb0f2-e3a0-452a-bf7d-e49dbb56843e
title: Status Server Monitor Issues
domain: agentictoolkit://cookbook/status-server/monitor/issues
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Records the board's derived verdict into the durable issues ledger — opens,
  refreshes, and resolves rows, repairs duplicate open rows, and fail-softs per target.
platforms:
- typescript
- web
tags:
- monitor
- ledger
- issues
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/data/constraints-and-validation
- agenticdevelopercookbook://guidelines/implementing/observability/logging
related:
- agentictoolkit://cookbook/status-server/monitor/alerts
- agentictoolkit://cookbook/status-server/monitor/issue-sources
- agentictoolkit://cookbook/status-server/board
- agentictoolkit://cookbook/status-server/monitor/cycle-runner
- agentictoolkit://cookbook/status-server/libsql
references:
- packages/web/packages/status-server/src/monitor/issues.ts (agentictoolkit)
- packages/web/packages/status-server/test/issues.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Issues

## Overview

`issues.ts` (`packages/web/packages/status-server/src/monitor/issues.ts`) is the status backend's issue ledger writer. Its own header comment states the design it replaced: `issues` used to be where a Problem was DECIDED; that verdict now lives in `deriveBoard` (`src/board/`), and this file only RECORDS the board's verdict. It keeps three things a derived board cannot hold on its own: alert dedup (via the `uniq_open_issue_per_target` partial unique index), the onset time a problem started, and 90 days of resolved history. The raw reads/writes live behind the `storage.issues` port (`storage/ports.ts`, implemented by the libSQL store); this file is the business logic layered on top of those CRUD primitives — which row is canonical, when to alert, and when a close must stay silent.

The module exports exactly two functions. `openByTarget(storage)` reads every currently-open row and groups it by target, oldest-first, so index `0` per target is the canonical row (the one carrying the true onset) and anything after it is a shadow — `applyBoardToLedger` takes one such snapshot per invocation rather than re-querying per row, and the function is exported only so tests can assert the ledger through the same view the writer uses. `applyBoardToLedger(storage, board)` is the sole write entry point: for every target the board currently flags (`board.problems`) it opens a new row or refreshes the existing one, and for every target that has an open row but is no longer flagged it resolves that row — as a genuine recovery when the board still watches the target, silently as `unmonitored` when it does not. It is called from exactly one place in the codebase, `board/reconcile.ts`'s `reconcileBoardLedger`, which itself runs from the monitor's own `Worker` cycle (`cycle-runner.ts`) and from several API-thread call sites (`POST /board/reconcile`, config mutations that can strand an issue, and MCP tools) — `reconcileBoardLedger` also owns flushing the alerts this file queues, because "the cycle will flush" is false for most of those callers.

## Behavioral Requirements

### Reading the Ledger (`openByTarget`)

- **open-issues-grouped-by-target**: `openByTarget` MUST call `storage.issues.listOpen()` once and return a `Map<string, IssueRow[]>` in which every returned `IssueRow` appears exactly once, keyed by its own `target` field.
- **open-issues-oldest-first**: For a given target, the `IssueRow[]` list `openByTarget` returns MUST preserve the order `storage.issues.listOpen()` produced (oldest `openedAt`, then `id`, per that port method's own contract) — so element `0` of each list is always the canonical row.
- **open-issues-preserves-duplicates**: `openByTarget` MUST NOT deduplicate, drop, or merge rows that share a target, even though `uniq_open_issue_per_target` is meant to guarantee at most one open row per target. Per the function's own doc comment, the index "has been violated in practice (pre-migration rows, manual backfills)," and dropping the extras is exactly what let a shadow row rot: never updated, never resolved, invisible to the very repair cycle whose job it is to close it.
- **single-open-snapshot-per-apply**: `applyBoardToLedger` MUST call `openByTarget` exactly once per invocation and decide every target's open/update/resolve action against that one snapshot (`open`), never issuing a second `listOpen()`-derived read mid-run.

### Data Shapes

- **open-input-shape**: An `OpenInput` value MUST carry exactly these fields: `target: string`, `source: IssueSource`, `name: string`, `environment: string | null`, `severity: string`, `state: string`, `statusCode: number | null`, `detail: string | null`, `sourceUrl: string | null`, `liveUrl: string | null`, plus the optional `commitHash?: string | null`, `commitMessage?: string | null`, `commitRepo?: string | null`. Per the type's own comment, the three commit fields are the ones a deploy-failure issue carries; the `http`/`dns`/`stale` sources omit them, so they default to absent on that literal rather than being required.
- **apply-board-to-ledger-return-shape**: `applyBoardToLedger` MUST resolve to exactly `{ opened: number; updated: number; resolved: number; resolvedTargets: string[] }`, with no additional or missing keys.

### Opening a New Problem

- **insert-on-absent-open-row**: For each `[target, p]` entry of `board.problems`, when `open.get(target)` yields no rows (`rows[0]` is `undefined`), `applyBoardToLedger` MUST call `storage.issues.insertIssue` with an `OpenInput` built from `p`'s `target`, `source`, `name`, `environment`, `severity`, `state`, `statusCode`, `detail`, `sourceUrl`, `liveUrl`, `commitHash`, `commitMessage`, and `commitRepo` — copied verbatim, never re-derived — and MUST increment the returned `opened` count only after that call resolves without throwing.
- **insert-relies-on-conflict-guard**: `openIssue` MUST call `storage.issues.insertIssue` without first checking whether an open row already exists for that target; per its own comment, `insertIssue` itself "guards the partial unique index against a race (onConflictDoNothing)," so the race guard is the storage primitive's responsibility, not a check this file duplicates.
- **open-alerts-unconditionally**: `openIssue` MUST call `notifyIssueAlert` with `kind: 'opened'` every time `insertIssue` resolves without throwing, unconditionally — never gated on whether alert delivery is currently configured (that decision belongs to `flushAlerts`, external to this file).
- **open-alert-fields-from-input**: The `opened` alert `openIssue` queues MUST carry `target`, `name`, `environment`, `state`, and `detail` copied from the same `OpenInput` value (`v`) just inserted, never re-read from storage after the insert.

### Refreshing an Open Row

- **update-on-existing-open-row**: When `open.get(target)` yields at least one row (`cur = rows[0]`), `applyBoardToLedger` MUST call `storage.issues.updateIssue(cur.id, ...)` — never `insertIssue` — passing `p`'s `source`, `name`, `environment`, `severity`, `state`, `statusCode`, `detail`, `sourceUrl`, and `liveUrl` verbatim. Per the source comment, this includes refreshing `environment` and `name` even though neither is part of the row's identity: both are derived from the roster entry and the deploy row, so a row opened under a stale derivation must not keep the wrong tier badge or an upstream-renamed project's old name for as long as it stays open.
- **update-commit-fields-default-null**: `updateIssue` MUST pass `v.commitHash ?? null`, `v.commitMessage ?? null`, and `v.commitRepo ?? null` to `storage.issues.updateIssue` — an `undefined` commit field on the current Problem MUST be written as `null`, never left unset, on every refresh of an open row (`IssuePatch` requires all three; `OpenInput` makes them optional).
- **update-never-touches-resolution**: `updateIssue` MUST NOT call `storage.issues.resolveIssue` and MUST NOT change the row's onset (`openedAt`); a target that keeps matching a Problem across cycles is refreshed in place on its original row, never closed and reopened.
- **update-does-not-alert**: `updateIssue` MUST NOT call `notifyIssueAlert`; refreshing an open row's derived fields is not a state transition and MUST NOT page on-call.

### Shadow Row Repair (`closeShadows`)

- **close-shadows-targets-non-canonical-rows**: `closeShadows(storage, rows)` MUST iterate `rows.slice(1)` only — every row except the canonical `rows[0]` — leaving the canonical row completely untouched by this function.
- **shadow-resolution-reason-duplicate**: For each row `closeShadows` retires, it MUST call `resolveIssue(storage, dup, "duplicate")`.
- **duplicate-resolution-silent**: Because `resolveIssue` only calls `notifyIssueAlert` when its `reason` argument is `"recovered"`, retiring a shadow with reason `"duplicate"` MUST NOT queue any alert.
- **shadow-retirement-logged**: For each shadow row it retires, `closeShadows` MUST call `console.warn` with exactly the message `` `[ledger] retired duplicate open issue #${dup.id} for ${dup.target} — uniq_open_issue_per_target should have prevented it` ``.
- **shadows-closed-on-both-ledger-paths**: `applyBoardToLedger` MUST call `closeShadows(storage, rows)` for a target's full row list on both the still-flagged path (immediately after `updateIssue`) and the no-longer-flagged path (immediately after the canonical row's `resolveIssue`) — a shadow is stale either way, since only the canonical row is ever updated or resolved by the other paths.

### Resolving a Stale Target

- **stale-defined-by-absence-from-live**: `applyBoardToLedger` MUST treat a target as stale when it is a key of `open` (has at least one open row) and is NOT a key of `live` (the `Map` built from `board.problems`) — regardless of whether that target still appears in `board.monitoredTargets`.
- **resolve-reason-by-watched-membership**: For a stale target's canonical row, `applyBoardToLedger` MUST call `resolveIssue` with reason `"recovered"` when the target IS a member of the `Set` built from `board.monitoredTargets`, and with reason `"unmonitored"` when it is NOT — per the source comment, `"recovered"` means the thing being watched came back, while `"unmonitored"` means monitoring itself stopped (a token removed, a project un-wired), and conflating the two would tell on-call an outage cleared when it may still be burning.
- **resolve-alerts-only-on-recovery**: `resolveIssue` MUST call `notifyIssueAlert` with `kind: 'resolved'` only when its `reason` argument is `"recovered"`; for `"unmonitored"` or `"duplicate"` it MUST return without queuing any alert.
- **resolve-compares-full-target-string**: Staleness and watched-membership MUST both be decided by comparing the complete target string (`open.keys()` against `live`; the stale target against the `Set` from `board.monitoredTargets`) — never a sub-segment of it. Per the source comment, the deleted `issueOrphaned` compared only the project segment of a deploy target, so a Railway target whose environment left config survived every sweep and stayed open forever; comparing the whole string is what fixes that.
- **resolve-skips-target-with-no-open-row**: When a stale target's `open.get(t)` yields no rows (`cur` is `undefined`), `applyBoardToLedger` MUST skip it with `continue` before entering the write-isolating `try` block — no write is attempted and no failure is logged for it.

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

## Appearance

Not applicable — this is a server-side ledger writer, not a visual component.

## States

Not applicable — this is a server-side ledger writer, not a visual component; the states an issue row moves through (open, updated-in-place, resolved as recovered/unmonitored/duplicate) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side ledger writer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-issues-001 | insert-on-absent-open-row, apply-board-to-ledger-return-shape, open-alert-fields-from-input | `applyBoardToLedger(storage, board([httpProblem()], ['svc']))` against an empty ledger, where `httpProblem()` defaults to `target:'svc', source:'http', state:'down', statusCode:503` | Returns `{opened:1, updated:0, resolved:0, resolvedTargets:[]}`; exactly one open row exists with `target:'svc', state:'down', source:'http', resolvedAt:null` — `test/issues.test.ts` › "opens a row for a down service and resolves it on recovery" |
| status-server-monitor-issues-002 | update-on-existing-open-row, apply-board-to-ledger-return-shape, update-never-touches-resolution | After 001, call `applyBoardToLedger(storage, board([httpProblem({state:'degraded', statusCode:null, detail:'slow: 1200ms'})], ['svc']))` | Returns `{opened:0, updated:1, resolved:0}`; still exactly one open row, now with `state:'degraded'` and `detail:'slow: 1200ms'` — the row is not duplicated — `test/issues.test.ts` › "keeps ONE open row per target across repeated bad boards" |
| status-server-monitor-issues-003 | resolve-reason-by-watched-membership, resolve-alerts-only-on-recovery | After 001, call `applyBoardToLedger(storage, board([], ['svc']))` (still watched, no longer flagged) | Returns `{resolved:1}`; the row's `resolvedAt` is non-null and `resolvedReason` is exactly `'recovered'`; `notifyIssueAlert` is called once with `kind:'resolved'` — `test/issues.test.ts` › "opens a row for a down service and resolves it on recovery", step 2 |
| status-server-monitor-issues-004 | resolve-reason-by-watched-membership, resolve-alerts-only-on-recovery | Insert an open row for target `'vercel\|gone\|'`, then call `applyBoardToLedger(storage, board([], []))` (target absent from `monitoredTargets`) | The row's `resolvedReason` is `'unmonitored'`; `notifyIssueAlert` is NOT called — `test/issues.test.ts` › "closes a de-configured target SILENTLY, but a recovered one alerts" |
| status-server-monitor-issues-005 | resolve-compares-full-target-string | Insert an open row for `target:'railway\|adh-backend\|scratch1'`, then call `applyBoardToLedger` with a board whose `monitoredTargets` is `['railway\|adh-backend\|production']` (same project, different environment) and `problems:[]` | The `scratch1` row's `resolvedAt` becomes non-null — the old project-only comparison would have left it open forever — `test/issues.test.ts` › "orphans a Railway target whose ENVIRONMENT left config" |
| status-server-monitor-issues-006 | resolve-skips-target-with-no-open-row | Call `applyBoardToLedger` with a board whose `monitoredTargets` and `problems` are both empty against an already-empty ledger | Returns `{opened:0, updated:0, resolved:0, resolvedTargets:[]}`; no storage write of any kind occurs and no failure is logged |
| status-server-monitor-issues-007 | per-target-write-isolation, write-failure-log-format, counts-reflect-landed-writes-only | `storage.insert` stubbed to throw on its first call only; call `applyBoardToLedger` with two new-open problems for targets `'ep-1'` and `'ep-2'` | Returns `{opened:1}`; only `'ep-2'` exists as an open row; `console.error` is called exactly once with a message starting `[ledger] write failed for ep-1` — `test/issues.test.ts` › "isolates a failed write — one bad target must not cost the cycle its tail" |
| status-server-monitor-issues-008 | per-target-write-isolation, counts-reflect-landed-writes-only | Two open rows exist (`ep-1`, `ep-2`), both now stale; `storage.update` stubbed to throw on its first call only; call `applyBoardToLedger` with an empty board | Returns `{resolved:1, resolvedTargets:['ep-2']}`; `ep-1` remains open — `test/issues.test.ts` › "counts only the rows that actually closed" |
| status-server-monitor-issues-009 | open-issues-grouped-by-target, open-issues-oldest-first, open-issues-preserves-duplicates | Two open rows for the same target `'svc'` exist (`uniq_open_issue_per_target` dropped for the test), inserted newest-first with `detail:'shadow'` at `openedAt` 9000 and `detail:'canonical'` at `openedAt` 2000; call `(await openByTarget(storage)).get('svc')` | Returns both rows as an array in the order `['canonical', 'shadow']` by `detail` — oldest first, both present — `test/issues.test.ts` › "openByTarget keeps every row, oldest first" |
| status-server-monitor-issues-010 | close-shadows-targets-non-canonical-rows, shadow-resolution-reason-duplicate, duplicate-resolution-silent, shadows-closed-on-both-ledger-paths, updated-requires-shadow-closure-success | From the two-open-row state in 009, call `applyBoardToLedger` with a board still flagging `'svc'` as down | Returns `{opened:0, updated:1}`; the canonical row's `detail` updates to the new value with `resolvedReason:null`; the shadow row's `resolvedReason` becomes `'duplicate'`; no `resolved`-kind alert is queued — `test/issues.test.ts` › "a still-failing target updates the canonical row and retires the shadow" |
| status-server-monitor-issues-011 | resolve-canonical-then-shadows (shadows-closed-on-both-ledger-paths), resolved-targets-recorded-before-shadow-closure, duplicate-resolution-silent | From the two-open-row state in 009, call `applyBoardToLedger` with a board that no longer flags `'svc'` and still watches it | Returns `{resolved:1}`; both rows' `resolvedAt` become non-null, with `resolvedReason` values `['recovered', 'duplicate']` in canonical-then-shadow order; exactly one `resolved`-kind alert is queued, not two — `test/issues.test.ts` › "a recovered target closes BOTH rows and alerts exactly once" |
| status-server-monitor-issues-012 | shadow-retirement-logged | From the two-open-row state in 009, trigger either ledger path (010 or 011) | `console.warn` is called once with a message matching `[ledger] retired duplicate open issue #<id> for svc — uniq_open_issue_per_target should have prevented it`, where `<id>` is the shadow row's numeric id |
| status-server-monitor-issues-013 | update-commit-fields-default-null | An open deploy row exists with `commitHash:'a'`; call `applyBoardToLedger` with a matching Problem whose `commitHash`, `commitMessage`, and `commitRepo` are each `undefined` on the `OpenInput` `updateIssue` receives | `storage.issues.updateIssue` is called with `commitHash: null, commitMessage: null, commitRepo: null` — never `undefined` |
| status-server-monitor-issues-014 | update-on-existing-open-row | An open row exists with `environment:'production', name:'hub-help-testing'` for target `vercel\|hub-help-testing\|`; call `applyBoardToLedger` with a Problem for the same target carrying `environment:'testing'` | Returns `{opened:0, updated:1}`; the row's `environment` becomes `'testing'` — `test/issues.test.ts` › "refreshes an open row's environment, so a re-derived tier is not frozen at open time" |
| status-server-monitor-issues-015 | update-on-existing-open-row | An open row exists with `name:'hub-web'` for target `vercel\|prj_abc\|`; call `applyBoardToLedger` with a Problem for the same target carrying `name:'hub-web-v2'` | Returns `{opened:0, updated:1}`; the row's `name` becomes `'hub-web-v2'` — `test/issues.test.ts` › "refreshes an open row's NAME too, so an upstream rename is not frozen at open time" |
| status-server-monitor-issues-016 | reapply-is-idempotent | Call `applyBoardToLedger(storage, b)` with an unchanged board `b`, then call it again with the same `b` | The second call returns `opened:0`; the total row count after both calls equals the count after the first — `test/issues.test.ts` › "is idempotent — re-applying the same board opens nothing new" |
| status-server-monitor-issues-017 | open-issues-grouped-by-target, single-open-snapshot-per-apply, insert-on-absent-open-row | A board with a Problem whose `source` is `'dns'` for a target with no existing open row | The inserted row's `source` column is exactly `'dns'` — the ledger writes the Problem's own source rather than re-deriving one from the state word — `test/issues.test.ts` › "records the Problem's own source, so a DNS failure lands as a dns row" |
| status-server-monitor-issues-018 | open-alerts-unconditionally, update-does-not-alert, resolve-alerts-only-on-recovery | Run three successive cycles against the same real recorder path: (1) a board flags a new down endpoint, (2) the same board is applied again unchanged, (3) the board reports the endpoint healthy | `notifyIssueAlert` is called exactly twice total — once with `kind:'opened'` after cycle 1, once with `kind:'resolved'` after cycle 3 — cycle 2 queues nothing |
| status-server-monitor-issues-019 | open-input-shape | `const bad: OpenInput = { target:'t', source:'http', name:'n', environment:null, severity:'major', state:'down', statusCode:null, detail:null, sourceUrl:null }` (missing `liveUrl`) | TypeScript compilation fails: property `liveUrl` is missing from type `OpenInput` |
| status-server-monitor-issues-020 | insert-relies-on-conflict-guard | `storage.issues.insertIssue` is a fake that itself performs an `onConflictDoNothing`-style no-op when a row for the target already exists; call `applyBoardToLedger` twice concurrently (via `Promise.all`) with the same new-open Problem for a target with no prior open row | Exactly one open row exists afterward for that target — the second `insertIssue` call is absorbed by the storage-level guard, not by any check in `issues.ts` itself |

## Edge Cases

- **Null and empty input**: A Problem's `environment`, `detail`, `sourceUrl`, `liveUrl`, and the three commit fields may each be `null`; none of these is validated by this file — they are written to storage exactly as given, and `updateIssue` additionally coerces an `undefined` commit field to `null` (`update-commit-fields-default-null`) — MUST. A Problem's `target` or `name` being an empty string is not checked or rejected anywhere in this file; an empty-string target groups under the empty-string key in `openByTarget`'s `Map` and is written to storage as-is — MUST (this file performs no non-emptiness validation of any field it writes).
- **Boundary values**: There is no numeric or size boundary internal to this file — no cap on the number of targets processed per `applyBoardToLedger` call, no cap on shadow rows `closeShadows` will retire for one target. A target with exactly one open row (the ordinary case) and a target with two or more (the duplicate-row repair path) are the only cardinalities this file distinguishes, via `rows[0]` vs. `rows.slice(1)` — MUST.
- **Concurrent access**: Within a single Node process, `applyBoardToLedger`'s per-target loops do not interleave with each other (JavaScript's single-threaded execution model), so the ordering of the `try/catch` and the `updated++`/`resolvedTargets.push` accounting described under Fail-Soft Isolation and Reporting is deterministic for any one call — MUST. Across two separate invocations of `applyBoardToLedger` (potentially from different threads or processes sharing the same underlying storage, per `board/reconcile.ts`'s own documented call sites), this file provides no compare-and-swap, version check, or transaction linking a target's `openByTarget` read to its later write, beyond the database's own partial unique index guarding `insertIssue` specifically — see the open question on concurrent-write-ordering above.
- **Error states**: A thrown or rejected storage call for one target (insert, update, resolve, or a shadow's resolve) is caught within that target's own iteration, logged via `console.error` in the exact `write-failure-log-format`, and that target is excluded from the returned counts — the loop continues to the next target rather than aborting the whole call — MUST (`per-target-write-isolation`). This file never retries a failed write itself; per its own comment, a skipped row is recoverable because the board is derived and will re-derive and rewrite it on the next cycle — MUST.
- **Offline / disconnected state**: This file makes no network call of its own; its only dependency is the injected `Storage` port, whose underlying transport (a remote libSQL connection) can be unreachable. An unreachable storage manifests identically to any other thrown storage error and is handled the same way — caught, logged, and skipped per target — MUST. This file has no notion of "reconnecting" or buffering writes for a later retry; a target skipped due to storage unavailability is simply re-attempted whenever `applyBoardToLedger` is next called (the next monitor cycle or reconcile), not by any mechanism inside this file.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` (parameter to `openByTarget` and `applyBoardToLedger`) | `Storage` | none — caller-supplied | The persistence port this file writes through; every call in this file reaches storage exclusively via `storage.issues.*`. This file never constructs or configures a `Storage` implementation itself. |
| `board` (parameter to `applyBoardToLedger`) | `Board` | none — caller-supplied | The derived verdict to record — produced by `deriveBoard` from board facts, external to this file, and passed in unchanged by `board/reconcile.ts`'s `reconcileBoardLedger`. |

This file reads no environment variable and defines no module-level constant of its own; every configurable value (the alert webhook URL, retention windows, probe cadence) belongs to `alerts.ts`, `maintenance-store.ts`, or `config/env.ts`, all external to this file.

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it only writes rows to a database table that other, external modules later expose over HTTP or MCP.

## Localization

Not applicable: the only string literals this file constructs are the `console.warn`/`console.error` diagnostic messages under `shadow-retirement-logged` and `write-failure-log-format`. These are operator-facing server log lines, never rendered to an end user and never sent in the `notifyIssueAlert` webhook payload — `notifyIssueAlert`'s `target`/`name`/`environment`/`state`/`detail` fields are structured data this file copies from its inputs, not text it composes for display; the alert's rendered text is `alerts.ts`'s concern, a separate file.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system. Whether alerting is delivered at all is decided by `flushAlerts`'s caller-supplied URL (`alerts.ts`, external to this file), not by any flag this file checks.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind; telemetry collection lives in `../telemetry`, external to this file.

## Privacy

- **Data collected**: the fields this file reads from a `Problem` and writes to an `IssueRow` — `target`, `source`, `name`, `environment`, `severity`, `state`, `statusCode`, `detail`, `sourceUrl`, `liveUrl`, `commitHash`, `commitMessage`, `commitRepo` — are infrastructure and deploy metadata describing a monitored site's or project's health, sourced from the board's derivation of provider APIs and roster configuration. None of it is entered by an end user of the monitored product, and this file never constructs, reads, or transmits a credential or token.
- **Storage**: persisted durably to the `issues` table through the injected `Storage` port (the libSQL store, external to this file). An open row survives a process restart; a resolved row is retained for 90 days (`ISSUE_RESOLVED_RETENTION_DAYS`, enforced by `maintenance-store.ts`'s retention prune, external to this file) before it is deleted.
- **Transmission**: this file makes no network call itself. Opening a new problem, or resolving one as a genuine recovery, queues an `IssueAlert` via `notifyIssueAlert` (`alerts.ts`) that a later, separately-invoked `flushAlerts` call may transmit off-box to an operator-configured webhook — this file only decides whether to queue an alert, never sends one.
- **Retention**: an open row has no expiry and persists until this module resolves it; a resolved row is retained for 90 days before the external retention prune deletes it. This file implements neither the prune nor any backup mechanism for the `issues` table.

## Logging

This file uses plain `console.warn`/`console.error` calls with a literal `[ledger]` prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| A shadow row retired for a target that already had a canonical open row | warn (`console.warn`) | `[ledger] retired duplicate open issue #<id> for <target> — uniq_open_issue_per_target should have prevented it` |
| A storage write (insert, update, or resolve) threw for one target | error (`console.error`) | `[ledger] write failed for <target> — skipped, the next cycle re-derives it: <error message>` |

A successful open, update, or recovered/unmonitored resolve produces no log output at all, at any level.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend or service embedding this ledger pattern would model `OpenInput` and `IssueRow` as `Sendable` structs, express the `Storage.issues` port as a protocol with an `actor`-isolated conformer over its SQLite/libSQL-backed store, and give `applyBoardToLedger` the same per-target isolation using a Swift `do { ... } catch { logLedgerFailure(target, error) }` inside a `for` loop over the board's problems, `await`-ing each storage call in turn.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin/JVM port models `OpenInput`/`IssueRow` as `data class`es, `Storage.issues` as an interface backed by a suspendable store (Room/SQLDelight or Exposed), reuses `groupBy` for `openByTarget`'s target-keyed grouping, and makes `applyBoardToLedger` a `suspend fun` whose per-target `try { ... } catch (e: Exception) { logLedgerFailure(target, e) }` inside a `for` loop preserves the same fail-soft isolation across coroutine calls.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/issues.ts` as a set of exported and private `async` functions with no class and no framework dependency of its own. It is called exclusively through `board/reconcile.ts`'s `reconcileBoardLedger`, which in turn runs from the monitor's `Worker` cycle (`cycle-runner.ts`) and from several API-thread routes and MCP tools. It depends on `Storage.issues` (`storage/ports.ts`, implemented in `libsql/stores/issue-store.ts`) and on `notifyIssueAlert` (`alerts.ts`).
- **AppKit / UIKit**: same non-UI framing as SwiftUI. This file holds no in-memory state between calls of its own — unlike the sibling alerts recipe's module-level queue, which is per-`Worker`-thread in Node — so a Swift service embedding this pattern needs no analogue to that per-thread isolation concern; every call to `applyBoardToLedger` is a self-contained read-then-write against the shared database.
- **WinUI 3**: a .NET port models `OpenInput` as a `record` with the same fields (`CommitHash`/`CommitMessage`/`CommitRepo` as nullable `string?` properties, defaulted to `null` in a constructor or `with`-expression rather than left unset), `IssueRow` as a `record` returned by a `Task<IReadOnlyList<IssueRow>> ListOpenAsync()` method on an `IIssueStore` interface (the `Storage.issues` port's analogue), and `ApplyBoardToLedgerAsync(IStorage storage, Board board)` as an `async Task<LedgerCounts>` that loops `board.Problems` with `try { ... } catch (Exception ex) { LogLedgerFailure(target, ex); }` per target — mirroring the fail-soft isolation exactly. The `uniq_open_issue_per_target` partial unique index's `ON CONFLICT DO NOTHING` guard needs an explicit unique index plus a caught `DbUpdateException` (EF Core) or `SqliteException` to reproduce with `System.Text.Json`/ADO.NET, since neither has a direct equivalent to Drizzle's `onConflictDoNothing`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/issues.ts` |

## Design Decisions

- **Decision**: keep `issues` as a ledger that only records the board's verdict, rather than letting `deriveBoard`'s output replace it outright.
  **Rationale**: stated directly in the file's own header comment — the ledger keeps three things a derived board cannot: alert dedup via `uniq_open_issue_per_target`, the onset time a problem started, and 90 days of resolved history. A purely derived board recomputed from scratch each cycle has no memory of any of the three.
  **Approved**: pending
- **Decision**: give `applyBoardToLedger` and `openByTarget` no injectable clock (`nowMs`) parameter, unlike `deriveBoard`.
  **Rationale**: the source comment draws the line explicitly — the rule that makes the clock a parameter exists for `deriveBoard`, which must be pure so the regression suite can drive it deterministically. This function exists to write rows, and each of its three storage primitives stamps its own `new Date()`; accepting a `nowMs` this function cannot hand to any of them would document a guarantee it does not make.
  **Approved**: pending
- **Decision**: compare the FULL target string when deciding staleness and watched-membership, rather than a sub-segment (e.g., just the project portion).
  **Rationale**: the source comment explains this replaced the deleted `issueOrphaned`, which compared only the project segment for deploy targets and let a Railway target whose environment left config survive every sweep, staying open forever. Comparing the whole string is what a target key with an environment segment requires.
  **Approved**: pending
- **Decision**: repair duplicate open rows (`closeShadows`) rather than assuming `uniq_open_issue_per_target` makes them impossible.
  **Rationale**: the source comment on `openByTarget` states the index "has been violated in practice (pre-migration rows, manual backfills)," and a writer that only ever saw the first row per target let a shadow rot: never updated, never resolved, invisible to the cleanup cycle whose job it was to close it. Repairing on both the still-flagged and no-longer-flagged paths, silently and via a distinct `"duplicate"` resolution reason, means a violated invariant leaves a warning trail instead of being papered over.
  **Approved**: pending
- **Decision**: place the `updated`/`resolvedTargets` accounting on opposite sides of the `closeShadows` call — `updated++` after it, `resolvedTargets.push(t)` before it.
  **Rationale**: not stated in a comment; recorded here as an observed, deliberate-looking asymmetry in the source rather than an invented explanation. Its practical effect is that a `closeShadows` failure following a successful `updateIssue` costs that target its `updated` credit even though the canonical row's update already committed, while the same failure following a successful `resolveIssue` does NOT cost the target its place in `resolvedTargets` or the `resolved` count. Both behaviors are logged via `logLedgerFailure` either way, so no signal is lost — but a consumer of the returned counts (e.g. `POST /board/reconcile`'s caller) should read `updated` as "canonical write and shadow cleanup both succeeded" and `resolved`/`resolvedTargets` as "the canonical write succeeded" (shadow cleanup for a resolved target is a best-effort bonus, not a precondition of being counted).
  **Approved**: pending
- **Decision**: accept a one-time burst of duplicate `opened` alerts, and a resolved row's `environment` badge staying stale for up to 24 hours, as the deliberate cost of the deploy-target-key migration to `boardTargetKey`, rather than writing a data migration or one-shot alert suppression.
  **Rationale**: the source's own extended comment weighs both alternatives explicitly and rejects them — a data migration "buys one field, one time, and owes a correctness argument per family," and one-shot alert suppression "can only ever be exercised once, and whose failure mode is swallowing a real page." Because an old-spelled target is absent from the new `monitoredTargets`, it closes silently as `unmonitored` (correct — no recovery was observed), and the re-derived target then opens fresh and alerts unconditionally (`open-alerts-unconditionally`) — a one-time, expected burst on the deploy that ships this change, not corruption. The resolved-row environment staleness is self-clearing within `ACTIVITY_WINDOW_MS` (24h) because only open rows are refreshed by `updateIssue`.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

`unit-test-coverage` passes: `test/issues.test.ts` exercises `openByTarget`'s grouping and duplicate-preserving behavior, `applyBoardToLedger`'s open/update/resolve paths, the recovered-vs-unmonitored distinction, the full-target-string comparison fix for the old `issueOrphaned` bug, the per-row fail-soft isolation on both a failed insert and a failed update, and the shadow-row repair path with the unique index deliberately dropped. `separation-of-concerns` passes: this file owns exactly one concern — recording a verdict `deriveBoard` already reached — and reads no config and derives no Problem itself; the raw CRUD lives behind `storage.issues`, and the decision of WHEN a Problem exists lives entirely in `board/`, external to this file. `explicit-error-handling` passes: every storage call this file makes is wrapped in a `try/catch` that logs via `console.error`/`console.warn` with a specific, traceable message and excludes the failed target from the returned counts — no failure is silently dropped, though see `data-integrity` below for the accounting nuance that follows from where the catch boundary sits. `idempotent-operations` passes: `reapply-is-idempotent` is directly asserted by the test suite, and `reconcileBoardLedger`'s own doc comment states it is "safe to call on every mutation... calling it twice resolves nothing the second time." `fault-tolerance` passes: `per-target-write-isolation` is the file's central design decision, explicitly justified by what a propagated exception would cost the rest of the monitor cycle (`cycle-runner.ts`'s `finally` block). `data-integrity` is `partial`: this file actively repairs a violated database invariant (`uniq_open_issue_per_target`) rather than assuming it holds, which is a strength — but the repair mechanism itself has two open edges recorded above rather than fully resolved: the `updated`/`resolvedTargets` accounting asymmetry around `closeShadows` failures (Design Decisions), and the unaddressed concurrent-write-ordering question for `updateIssue`/`resolveIssue` (the `concurrent-write-ordering` marker under Behavioral Requirements), neither of which corrupts data outright but both of which mean this file's guarantees about a target's ledger state under concurrent or partially-failing writes are not fully specified.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
