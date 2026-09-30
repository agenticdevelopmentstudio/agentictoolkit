<!-- leaf: implement-status-server-monitor-1/issues · source: status-server-monitor-issues.md -->

**Rules** (cite as `implement-status-server-monitor-1/issues#<slug>`):

- `open-issues-grouped-by-target` MUST
- `open-issues-oldest-first` MUST
- `open-issues-preserves-duplicates` MUST
- `single-open-snapshot-per-apply` MUST
- `open-input-shape` MUST
- `apply-board-to-ledger-return-shape` MUST
- `insert-on-absent-open-row` MUST
- `insert-relies-on-conflict-guard` MUST
- `open-alerts-unconditionally` MUST
- `open-alert-fields-from-input` MUST
- `update-on-existing-open-row` MUST
- `update-commit-fields-default-null` MUST
- `update-never-touches-resolution` MUST
- `update-does-not-alert` MUST
- `close-shadows-targets-non-canonical-rows` MUST
- `shadow-resolution-reason-duplicate` MUST
- `duplicate-resolution-silent` MUST
- `shadow-retirement-logged` MUST
- `shadows-closed-on-both-ledger-paths` MUST
- `stale-defined-by-absence-from-live` MUST
- `resolve-reason-by-watched-membership` MUST
- `resolve-alerts-only-on-recovery` MUST
- `resolve-compares-full-target-string` MUST
- `resolve-skips-target-with-no-open-row` MUST

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

