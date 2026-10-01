---
id: 130fb0f2-e3a0-452a-bf7d-e49dbb56843e
title: Monitor Issues
domain: agentictoolkit://cookbook/status/service/monitor/issues
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/status/service/monitor/alerts
- agentictoolkit://cookbook/status/service/monitor/issue-sources
- agentictoolkit://cookbook/status/service/board
- agentictoolkit://cookbook/status/service/monitor/cycle-runner
- agentictoolkit://cookbook/status/service/storage/libsql
references:
- packages/web/packages/status-server/src/monitor/issues.ts (agentictoolkit)
- packages/web/packages/status-server/test/issues.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Monitor Issues

## Overview

This module is the status backend's issue ledger writer. It replaces an earlier design where the ledger itself decided whether a problem existed; that verdict now lives in the board-derivation logic, and this module only RECORDS the board's verdict. It keeps three things a derived board cannot hold on its own: alert dedup (via a partial unique index on open issues per target), the onset time a problem started, and 90 days of resolved history. The raw reads/writes live behind the storage layer's issues port; this module is the business logic layered on top of those CRUD primitives — which row is canonical, when to alert, and when a close must stay silent.

The module exports exactly two operations. Reading the ledger reads every currently-open row and groups it by target, oldest-first, so the first row per target is the canonical row (the one carrying the true onset) and anything after it is a shadow — applying the board to the ledger takes one such snapshot per invocation rather than re-querying per row, and the read is exposed separately only so tests can assert the ledger through the same view the writer uses. Applying the board to the ledger is the sole write entry point: for every target the board currently flags, it opens a new row or refreshes the existing one, and for every target that has an open row but is no longer flagged it resolves that row — as a genuine recovery when the board still watches the target, silently as `unmonitored` when it does not. It is called from exactly one place in the codebase, a board-reconciliation operation, which itself runs from the monitor's own cycle and from several concurrent call sites (a reconcile route, config mutations that can strand an issue, and other tool-driven entry points) — that reconciliation operation also owns flushing the alerts this module queues, because "the cycle will flush" is false for most of those callers.

## Behavioral Requirements

### Reading the Ledger

- **open-issues-grouped-by-target**: Reading the ledger MUST call the storage port's list-open operation once and return a map from target to its list of open rows, in which every returned row appears exactly once, keyed by its own target field.
- **open-issues-oldest-first**: For a given target, the list of open rows this read returns MUST preserve the order the storage port's list-open operation produced (oldest onset time, then row identity, per that operation's own contract) — so the first element of each list is always the canonical row.
- **open-issues-preserves-duplicates**: Reading the ledger MUST NOT deduplicate, drop, or merge rows that share a target, even though a partial unique index is meant to guarantee at most one open row per target. That index has been violated in practice (pre-migration rows, manual backfills), and dropping the extras is exactly what let a shadow row rot: never updated, never resolved, invisible to the very repair cycle whose job it is to close it.
- **single-open-snapshot-per-apply**: Applying the board to the ledger MUST read the ledger exactly once per invocation and decide every target's open/update/resolve action against that one snapshot, never issuing a second ledger read mid-run.

### Data Shapes

- **open-input-shape**: An open-input value MUST carry exactly these fields: target (string), source (an issue source), name (string), environment (string or absent), severity (string), state (string), status code (number or absent), detail (string or absent), source URL (string or absent), live URL (string or absent), plus the optional commit hash, commit message, and commit repository (each string or absent). The three commit fields are the ones a deploy-failure issue carries; the `http`/`dns`/`stale` sources omit them, so they default to absent on that value rather than being required.
- **apply-board-to-ledger-return-shape**: Applying the board to the ledger MUST resolve to exactly an opened count, an updated count, a resolved count, and a list of resolved targets, with no additional or missing fields.

### Opening a New Problem

- **insert-on-absent-open-row**: For each target and its problem in the board's problems, when the ledger snapshot yields no rows for that target, applying the board to the ledger MUST call the storage port's insert primitive with an open-input value built from the problem's target, source, name, environment, severity, state, status code, detail, source URL, live URL, commit hash, commit message, and commit repository — copied verbatim, never re-derived — and MUST increment the returned opened count only after that call resolves without throwing.
- **insert-relies-on-conflict-guard**: The open operation MUST call the storage port's insert primitive without first checking whether an open row already exists for that target; the insert primitive itself guards the partial unique index against a race (an insert-or-do-nothing guarantee), so the race guard is the storage primitive's responsibility, not a check this module duplicates.
- **open-alerts-unconditionally**: The open operation MUST queue an alert with kind `'opened'` every time the insert primitive resolves without throwing, unconditionally — never gated on whether alert delivery is currently configured (that decision belongs to the flush operation, external to this module).
- **open-alert-fields-from-input**: The `opened` alert the open operation queues MUST carry target, name, environment, state, and detail copied from the same open-input value just inserted, never re-read from storage after the insert.

### Refreshing an Open Row

- **update-on-existing-open-row**: When the ledger snapshot yields at least one row for a target, applying the board to the ledger MUST call the storage port's update primitive on the canonical row's identity — never the insert primitive — passing the problem's source, name, environment, severity, state, status code, detail, source URL, and live URL verbatim. This includes refreshing environment and name even though neither is part of the row's identity: both are derived from the roster entry and the deploy row, so a row opened under a stale derivation must not keep the wrong tier badge or an upstream-renamed project's old name for as long as it stays open.
- **update-commit-fields-default-null**: The update primitive MUST receive the commit hash, commit message, and commit repository each coerced to an explicit absent value rather than left unset — an unset commit field on the current problem MUST be written as an explicit absent value, never left unset, on every refresh of an open row (the update-input shape requires all three explicitly; the open-input shape makes them optional).
- **update-never-touches-resolution**: The update path MUST NOT call the storage port's resolve primitive and MUST NOT change the row's onset time; a target that keeps matching a problem across cycles is refreshed in place on its original row, never closed and reopened.
- **update-does-not-alert**: The update path MUST NOT queue an alert; refreshing an open row's derived fields is not a state transition and MUST NOT page on-call.

### Shadow Row Repair

- **close-shadows-targets-non-canonical-rows**: The shadow-repair operation MUST iterate every row except the canonical (first) row only, leaving the canonical row completely untouched by this operation.
- **shadow-resolution-reason-duplicate**: For each row the shadow-repair operation retires, it MUST call the resolve primitive with reason `"duplicate"`.
- **duplicate-resolution-silent**: Because the resolve path only queues an alert when its reason argument is `"recovered"`, retiring a shadow with reason `"duplicate"` MUST NOT queue any alert.
- **shadow-retirement-logged**: For each shadow row it retires, the shadow-repair operation MUST log a warning with exactly the message `` `[ledger] retired duplicate open issue #${dup.id} for ${dup.target} — uniq_open_issue_per_target should have prevented it` ``.
- **shadows-closed-on-both-ledger-paths**: Applying the board to the ledger MUST call the shadow-repair operation for a target's full row list on both the still-flagged path (immediately after the update primitive) and the no-longer-flagged path (immediately after the canonical row's resolve) — a shadow is stale either way, since only the canonical row is ever updated or resolved by the other paths.

### Resolving a Stale Target

- **stale-defined-by-absence-from-live**: Applying the board to the ledger MUST treat a target as stale when it has at least one open row and is NOT among the targets the board currently flags — regardless of whether that target still appears in the board's monitored targets.
- **resolve-reason-by-watched-membership**: For a stale target's canonical row, applying the board to the ledger MUST resolve it with reason `"recovered"` when the target IS a member of the board's monitored targets, and with reason `"unmonitored"` when it is NOT — `"recovered"` means the thing being watched came back, while `"unmonitored"` means monitoring itself stopped (a token removed, a project un-wired), and conflating the two would tell on-call an outage cleared when it may still be burning.
- **resolve-alerts-only-on-recovery**: The resolve path MUST queue an alert with kind `'resolved'` only when its reason argument is `"recovered"`; for `"unmonitored"` or `"duplicate"` it MUST return without queuing any alert.
- **resolve-compares-full-target-string**: Staleness and watched-membership MUST both be decided by comparing the complete target string — never a sub-segment of it. An earlier, now-removed check compared only the project segment of a deploy target, so a target whose environment left config survived every sweep and stayed open forever; comparing the whole string is what fixes that.
- **resolve-skips-target-with-no-open-row**: When a stale target yields no open rows, applying the board to the ledger MUST skip it before entering the write-isolating boundary — no write is attempted and no failure is logged for it.

### Fail-Soft Isolation and Reporting

- **per-target-write-isolation**: For both the still-flagged loop (open/update) and the stale loop (resolve), a thrown error from any storage call for one target's iteration MUST be caught within that same iteration's isolation boundary and MUST NOT prevent applying the board to the ledger from processing every other target. An exception escaping this operation would propagate past the monitor cycle's own cleanup step, skipping peer collection, telemetry collection, and the maintenance store's retention prune and heartbeat ping — and retention pruning silently stopping is what previously drove the per-tick cost past the container's CPU quota.
- **write-failure-log-format**: A caught write failure MUST be reported via the failure-logging helper, which MUST log an error with exactly the message `` `[ledger] write failed for ${target} — skipped, the next cycle re-derives it: ${err instanceof Error ? err.message : String(err)}` ``.
- **counts-reflect-landed-writes-only**: The opened, updated, and resolved counts, and the resolved-targets list, MUST reflect only writes that completed without throwing — a caught failure for a target MUST NOT be counted as opened, updated, or resolved, and MUST NOT add that target to the resolved-targets list.
- **updated-requires-shadow-closure-success**: Applying the board to the ledger MUST increment the updated count for a target only after BOTH the update primitive and the subsequent shadow-repair call for that target complete without throwing — because the updated count is incremented after the shadow-repair call in evaluation order, a shadow-repair failure following a successful update MUST cause that target's updated count to be omitted and MUST cause the failure-logging helper to log for it, even though the canonical row's update already committed to storage.
- **resolved-targets-recorded-before-shadow-closure**: Applying the board to the ledger MUST add a stale target to the resolved-targets list immediately after its canonical row's resolve call succeeds and BEFORE calling the shadow-repair operation for that target. Because that addition happens before the shadow-repair call in evaluation order, a subsequent shadow-repair failure for the same target MUST NOT remove it from the resolved-targets list or from the resolved count, even though the failure-logging helper still logs a write failure for that target — unlike the updated count above, whose accounting is the opposite way around.

### Determinism

- **reapply-is-idempotent**: Invoking the apply operation twice in succession with an unchanged board (the same problems and monitored targets) MUST return an opened count of `0` on the second call and MUST leave the ledger's row count unchanged, because the target already has a matching open row that the second call only refreshes.
- **no-injected-clock**: Neither the apply operation nor the ledger read MUST accept a caller-supplied clock parameter; every timestamp either operation's underlying storage primitives write MUST come from that primitive's own current-time reading at the moment it runs. The rule requiring an injectable clock applies to the board-derivation logic, which must be pure for the regression suite — this operation is the opposite kind, one that exists to write rows, and giving it a caller-supplied time it cannot hand to any of its three primitives would document a guarantee it does not make.

### Concurrency

- **concurrent-write-ordering**: NEEDS REVIEW: Not implemented in source. The open operation's insert is guarded against a concurrent race by the database's partial unique index via an insert-or-do-nothing guarantee, but the update and resolve primitives carry no equivalent guard — no compare-and-swap, version check, or transaction ties a target's read (via the ledger read) to its later write. The board-reconciliation operation (this operation's sole caller) is documented as running from both the monitor's own isolated execution context and several concurrent call sites against the same underlying storage, so two apply-operation invocations racing on the same target's open row are a real possibility, not a hypothetical one. What happens when they do — whether the second write's plain last-write-wins overwrite of the first is acceptable (both are honest projections of the board at each caller's own read time) or needs an optimistic-lock/transaction — is not stated anywhere in this module or its callers. Settled by confirming with the status-server maintainers whether the board-reconciliation operation's call sites are expected to genuinely overlap in production traffic.

## Appearance

Not applicable — this is a server-side ledger writer, not a visual component.

## States

Not applicable — this is a server-side ledger writer, not a visual component; the states an issue row moves through (open, updated-in-place, resolved as recovered/unmonitored/duplicate) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side ledger writer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-issues-001 | insert-on-absent-open-row, apply-board-to-ledger-return-shape, open-alert-fields-from-input | Apply a board with one down-http problem for target `svc` (state `down`, status code `503`) against an empty ledger | Returns opened `1`, updated `0`, resolved `0`, resolved-targets empty; exactly one open row exists with target `svc`, state `down`, source `http`, not resolved |
| status-server-monitor-issues-002 | update-on-existing-open-row, apply-board-to-ledger-return-shape, update-never-touches-resolution | After 001, apply a board with the same problem now `degraded`, no status code, detail `slow: 1200ms` | Returns opened `0`, updated `1`, resolved `0`; still exactly one open row, now with state `degraded` and detail `slow: 1200ms` — the row is not duplicated |
| status-server-monitor-issues-003 | resolve-reason-by-watched-membership, resolve-alerts-only-on-recovery | After 001, apply a board with no problems, still watching `svc` | Returns resolved `1`; the row is resolved, with reason exactly `'recovered'`; an alert is queued once with kind `'resolved'` |
| status-server-monitor-issues-004 | resolve-reason-by-watched-membership, resolve-alerts-only-on-recovery | Insert an open row for a target no longer in the roster, then apply a board with no problems and no monitored targets | The row's resolved reason is `'unmonitored'`; no alert is queued |
| status-server-monitor-issues-005 | resolve-compares-full-target-string | Insert an open row for a deploy target in one environment, then apply a board whose monitored targets name the same project in a different environment, with no problems | The row becomes resolved — the old project-only comparison would have left it open forever |
| status-server-monitor-issues-006 | resolve-skips-target-with-no-open-row | Apply a board with no monitored targets and no problems against an already-empty ledger | Returns opened `0`, updated `0`, resolved `0`, resolved-targets empty; no storage write of any kind occurs and no failure is logged |
| status-server-monitor-issues-007 | per-target-write-isolation, write-failure-log-format, counts-reflect-landed-writes-only | The insert primitive is stubbed to throw on its first call only; apply a board with two new-open problems for two targets | Returns opened `1`; only the second target exists as an open row; an error is logged exactly once with a message starting `[ledger] write failed for` naming the first target |
| status-server-monitor-issues-008 | per-target-write-isolation, counts-reflect-landed-writes-only | Two open rows exist, both now stale; the update primitive is stubbed to throw on its first call only; apply an empty board | Returns resolved `1`, with the resolved-targets list naming only the second target; the first target remains open |
| status-server-monitor-issues-009 | open-issues-grouped-by-target, open-issues-oldest-first, open-issues-preserves-duplicates | Two open rows for the same target exist (the partial unique index dropped for the test), inserted newest-first with detail `shadow` at the later onset time and detail `canonical` at the earlier onset time; read the ledger for that target | Returns both rows as a list in the order canonical, then shadow, by detail — oldest first, both present |
| status-server-monitor-issues-010 | close-shadows-targets-non-canonical-rows, shadow-resolution-reason-duplicate, duplicate-resolution-silent, shadows-closed-on-both-ledger-paths, updated-requires-shadow-closure-success | From the two-open-row state in 009, apply a board still flagging that target as down | Returns opened `0`, updated `1`; the canonical row's detail updates to the new value with resolved reason absent; the shadow row's resolved reason becomes `'duplicate'`; no `resolved`-kind alert is queued |
| status-server-monitor-issues-011 | resolve-canonical-then-shadows (shadows-closed-on-both-ledger-paths), resolved-targets-recorded-before-shadow-closure, duplicate-resolution-silent | From the two-open-row state in 009, apply a board that no longer flags that target and still watches it | Returns resolved `1`; both rows become resolved, with resolved reasons `'recovered'` then `'duplicate'` in canonical-then-shadow order; exactly one `resolved`-kind alert is queued, not two |
| status-server-monitor-issues-012 | shadow-retirement-logged | From the two-open-row state in 009, trigger either ledger path (010 or 011) | A warning is logged once with a message matching `[ledger] retired duplicate open issue #<id> for <target> — uniq_open_issue_per_target should have prevented it`, where `<id>` is the shadow row's numeric identity |
| status-server-monitor-issues-013 | update-commit-fields-default-null | An open deploy row exists with a commit hash set; apply a board with a matching problem whose commit hash, commit message, and commit repository are each left unset on the open-input value the update path receives | The update primitive is called with commit hash, commit message, and commit repository all explicitly absent — never left unset |
| status-server-monitor-issues-014 | update-on-existing-open-row | An open row exists with environment `production`, name `hub-help-testing`, for a given target; apply a board with a problem for the same target carrying environment `testing` | Returns opened `0`, updated `1`; the row's environment becomes `testing` |
| status-server-monitor-issues-015 | update-on-existing-open-row | An open row exists with name `hub-web` for a given target; apply a board with a problem for the same target carrying name `hub-web-v2` | Returns opened `0`, updated `1`; the row's name becomes `hub-web-v2` |
| status-server-monitor-issues-016 | reapply-is-idempotent | Apply an unchanged board, then apply the same board again | The second call returns opened `0`; the total row count after both calls equals the count after the first |
| status-server-monitor-issues-017 | open-issues-grouped-by-target, single-open-snapshot-per-apply, insert-on-absent-open-row | A board with a problem whose source is `'dns'` for a target with no existing open row | The inserted row's source column is exactly `'dns'` — the ledger writes the problem's own source rather than re-deriving one from the state word |
| status-server-monitor-issues-018 | open-alerts-unconditionally, update-does-not-alert, resolve-alerts-only-on-recovery | Run three successive cycles against the same real recorder path: (1) a board flags a new down endpoint, (2) the same board is applied again unchanged, (3) the board reports the endpoint healthy | An alert is queued exactly twice total — once with kind `'opened'` after cycle 1, once with kind `'resolved'` after cycle 3 — cycle 2 queues nothing |
| status-server-monitor-issues-019 | open-input-shape | Construct an open-input value with every required field except live URL | Construction is rejected: live URL is missing from the required shape |
| status-server-monitor-issues-020 | insert-relies-on-conflict-guard | The insert primitive is a fake that itself performs an insert-or-do-nothing no-op when a row for the target already exists; apply the same new-open problem for a target with no prior open row from two concurrent invocations | Exactly one open row exists afterward for that target — the second insert call is absorbed by the storage-level guard, not by any check in this module itself |

## Edge Cases

- **Null and empty input**: A problem's environment, detail, source URL, live URL, and the three commit fields may each be absent; none of these is validated by this module — they are written to storage exactly as given, and the update path additionally coerces an unset commit field to an explicit absent value (`update-commit-fields-default-null`) — MUST. A problem's target or name being an empty string is not checked or rejected anywhere in this module; an empty-string target groups under the empty-string key in the ledger read's map and is written to storage as-is — MUST (this module performs no non-emptiness validation of any field it writes).
- **Boundary values**: There is no numeric or size boundary internal to this module — no cap on the number of targets processed per apply call, no cap on shadow rows the shadow-repair operation will retire for one target. A target with exactly one open row (the ordinary case) and a target with two or more (the duplicate-row repair path) are the only cardinalities this module distinguishes, via the first row versus every row after it — MUST.
- **Concurrent access**: Within a single execution context, the apply operation's per-target loops do not interleave with each other, so the ordering of the isolation boundary and the updated-count/resolved-targets accounting described under Fail-Soft Isolation and Reporting is deterministic for any one call — MUST. Across two separate invocations of the apply operation (potentially from different execution contexts sharing the same underlying storage, per the board-reconciliation operation's own documented call sites), this module provides no compare-and-swap, version check, or transaction linking a target's ledger read to its later write, beyond the database's own partial unique index guarding the insert primitive specifically — see the open question on concurrent-write-ordering above.
- **Error states**: A thrown or rejected storage call for one target (insert, update, resolve, or a shadow's resolve) is caught within that target's own iteration, logged as an error in the exact `write-failure-log-format`, and that target is excluded from the returned counts — the loop continues to the next target rather than aborting the whole call — MUST (`per-target-write-isolation`). This module never retries a failed write itself; a skipped row is recoverable because the board is derived and will re-derive and rewrite it on the next cycle — MUST.
- **Offline / disconnected state**: This module makes no network call of its own; its only dependency is the injected storage port, whose underlying transport (a remote database connection) can be unreachable. An unreachable storage manifests identically to any other thrown storage error and is handled the same way — caught, logged, and skipped per target — MUST. This module has no notion of "reconnecting" or buffering writes for a later retry; a target skipped due to storage unavailability is simply re-attempted whenever the apply operation is next called (the next monitor cycle or reconcile), not by any mechanism inside this module.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Storage (input to the ledger read and the apply operation) | the storage port | none — caller-supplied | The persistence port this module writes through; every call in this module reaches storage exclusively via the storage port's issues operations. This module never constructs or configures a storage implementation itself. |
| Board (input to the apply operation) | the board shape | none — caller-supplied | The derived verdict to record — produced by the board-derivation logic from board facts, external to this module, and passed in unchanged by the board-reconciliation operation. |

This module reads no environment variable and defines no module-level constant of its own; every configurable value (the alert webhook URL, retention windows, probe cadence) belongs to modules external to this one.

## Deep Linking

Not applicable: this module defines no application URL scheme or route of its own — it only writes rows to a database table that other, external modules later expose over HTTP or other tool-driven access.

## Localization

Not applicable: the only string literals this module constructs are the diagnostic log messages under `shadow-retirement-logged` and `write-failure-log-format`. These are operator-facing server log lines, never rendered to an end user and never sent in the alert-queueing payload — the alert's target/name/environment/state/detail fields are structured data this module copies from its inputs, not text it composes for display; the alert's rendered text is a separate module's concern.

## Accessibility Options

Not applicable: this module has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this module consults no feature-flag system. Whether alerting is delivered at all is decided by the flush operation's caller-supplied URL (external to this module), not by any flag this module checks.

## Analytics

Not applicable: this module emits no analytics or telemetry event of any kind; telemetry collection lives in a module external to this one.

## Privacy

- **Data collected**: the fields this module reads from a problem and writes to an issue row — target, source, name, environment, severity, state, status code, detail, source URL, live URL, commit hash, commit message, commit repository — are infrastructure and deploy metadata describing a monitored site's or project's health, sourced from the board's derivation of provider APIs and roster configuration. None of it is entered by an end user of the monitored product, and this module never constructs, reads, or transmits a credential or token.
- **Storage**: persisted durably to the issues table through the injected storage port (external to this module). An open row survives a process restart; a resolved row is retained for 90 days (enforced by an external retention prune) before it is deleted.
- **Transmission**: this module makes no network call itself. Opening a new problem, or resolving one as a genuine recovery, queues an alert via the alert-queueing operation that a later, separately-invoked flush call may transmit off-box to an operator-configured webhook — this module only decides whether to queue an alert, never sends one.
- **Retention**: an open row has no expiry and persists until this module resolves it; a resolved row is retained for 90 days before the external retention prune deletes it. This module implements neither the prune nor any backup mechanism for the issues table.

## Logging

This module logs warnings and errors with a literal `[ledger]` prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| A shadow row retired for a target that already had a canonical open row | warn | `[ledger] retired duplicate open issue #<id> for <target> — uniq_open_issue_per_target should have prevented it` |
| A storage write (insert, update, or resolve) threw for one target | error | `[ledger] write failed for <target> — skipped, the next cycle re-derives it: <error message>` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/service/monitor/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
