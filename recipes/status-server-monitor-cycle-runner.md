---
id: 99e2ec9b-b209-4af9-a7d9-f3c4cc5e27db
title: Status Server Monitor Cycle Runner
domain: agentictoolkit://recipes/status-server-monitor-cycle-runner
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Composes one monitor cycle from its collaborator modules — the endpoint-probe
  sweep every tick, plus peers, telemetry, maintenance and heartbeat on a full sync.
platforms:
- typescript
- web
tags:
- monitor
- cycle
- worker
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/concurrency/concurrency
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/observability/logging
- agenticdevelopercookbook://guidelines/implementing/code-quality/dependency-injection
related:
- agentictoolkit://recipes/status-server-monitor-alerts
references:
- packages/web/packages/status-server/src/monitor/cycle-runner.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/sync.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/heartbeat.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/alerts.ts (agentictoolkit)
- packages/web/packages/status-server/src/peers/fetch.ts (agentictoolkit)
- packages/web/packages/status-server/src/telemetry/server.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/maintenance-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/worker.ts (agentictoolkit)
- packages/web/packages/status-server/src/scheduler.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/status-server/test/heartbeat.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Cycle Runner

## Overview

`cycle-runner.ts` (`packages/web/packages/status-server/src/monitor/cycle-runner.ts`) exports one function, `runMonitorCycle`, which is the complete body of one monitor cycle. Its own header comment describes it as "the cheap endpoint probe every tick, the expensive deploy/peer/telemetry/maintenance phase only on a FULL sync (the cadence decision itself stays with the scheduler wiring in `index.ts`)." It is a pure composition root: it decides no cadence and owns no connection, it only sequences calls into `runCycle` (`sync.ts`), `flushAlerts` (`alerts.ts`), `fetchPeers` (`peers/fetch.ts`), `collectTelemetry` (`telemetry/server.ts`), and `pingHeartbeat` (`heartbeat.ts`), plus two `storage.maintenance` operations. The file's own comment states why it is factored out this way: "Extracted so the worker entry (`worker.ts`) is pure glue and this composition stays importable/testable without threads." A `StatusConfig` value arrives from the host — via `index.ts` on the API thread, via `worker.ts`'s `workerData` on the worker thread — and is threaded to every collaborator that needs a setting; the database connection itself stays behind the `Storage` parameter, which `runMonitorCycle` never threads through on its own.

## Behavioral Requirements

### Signature and Delegation

- **runs-core-sweep-first**: `runMonitorCycle(storage: Storage, opts: { fullSync: boolean; config: StatusConfig }): Promise<void>` MUST call `runCycle(storage, config, { skipDeploys: !opts.fullSync })` exactly once, and MUST do so before any other call in its body.
- **skip-deploys-mirrors-full-sync**: The `skipDeploys` value passed to `runCycle` MUST be the logical negation of `opts.fullSync` — `true` on a probe-only tick (`opts.fullSync` is `false`) and `false` on a full sync (`opts.fullSync` is `true`).
- **config-threaded-unchanged**: `runMonitorCycle` MUST pass the same `config` reference it received, unmodified, to `runCycle` and to `collectTelemetry`, and MUST pass `config.alertWebhookUrl` as the sole argument to `flushAlerts` and `config.heartbeatUrl` as the sole argument to `pingHeartbeat`.
- **no-connection-lifecycle-management**: `runMonitorCycle` MUST NOT open, close, tune, or otherwise manage the underlying database connection itself; every persistence operation it triggers MUST be reached exclusively through the `storage: Storage` parameter it was given.
- **resolves-void-on-success**: When every step it runs completes without throwing, `runMonitorCycle` MUST resolve its returned `Promise<void>` with no value; it defines no success payload beyond "did not reject."

### Alert Flush and Failure Propagation

- **alerts-flushed-every-call**: `runMonitorCycle` MUST call `flushAlerts(config.alertWebhookUrl)` exactly once, inside a `finally` block that wraps only the `runCycle` call, so the flush runs whether `runCycle` resolves or rejects.
- **core-sweep-failure-propagates**: If the `runCycle` call rejects, `runMonitorCycle` MUST rethrow that same rejection to its own caller after the `finally` block's `flushAlerts` call has completed, and MUST NOT execute any statement after the `try`/`finally` block for that call.

### Full-Sync-Only Phase

- **full-sync-phase-requires-success**: The peers/telemetry/maintenance/snapshot/heartbeat phase (`fetchPeers`, `collectTelemetry`, `storage.maintenance.runMaintenance`, `storage.maintenance.snapshotIfDue`, `pingHeartbeat`) MUST run when, and only when, `opts.fullSync` is `true` and the `runCycle` call did not reject; it MUST NOT run on a probe-only tick regardless of whether `runCycle` succeeded, and MUST NOT run at all when `runCycle` rejected, regardless of `opts.fullSync`.
- **full-sync-phase-sequential-order**: When the full-sync phase runs, `runMonitorCycle` MUST await, in exactly this order, `fetchPeers(storage)`, then `collectTelemetry(storage, config)`, then `storage.maintenance.runMaintenance()`, then `storage.maintenance.snapshotIfDue()`, then `pingHeartbeat(config.heartbeatUrl)` — each call fully awaited to completion before the next begins; none of the five MAY run concurrently with another.
- **heartbeat-last**: `pingHeartbeat(config.heartbeatUrl)` MUST be the last operation `runMonitorCycle` performs on a full sync; it MUST NOT be called until `fetchPeers`, `collectTelemetry`, `runMaintenance`, and `snapshotIfDue` have each completed without throwing.
- **maintenance-phase-failure-aborts-remainder**: If `storage.maintenance.runMaintenance()` rejects, `runMonitorCycle` MUST propagate that rejection to its caller and MUST NOT call `storage.maintenance.snapshotIfDue()` or `pingHeartbeat` for that cycle.
- **maintenance-uses-store-defaults**: `runMonitorCycle` MUST call `storage.maintenance.runMaintenance()` and `storage.maintenance.snapshotIfDue()` with no arguments, deferring every prune budget, chunk size, snapshot interval, and retention-count default entirely to the `MaintenanceStore` implementation it is handed.
- **maintenance-prune-logged-on-deletion**: `runMonitorCycle` MUST log, via `console.log`, the message `[maintenance] pruned <deleted> retention rows` — where `<deleted>` is `runMaintenance`'s resolved `deleted` count — when that count is greater than `0`, appending the literal suffix ` — more next cycle` when `runMaintenance`'s resolved `done` flag is `false`; it MUST NOT emit this log line when the resolved `deleted` count is `0`.

## Appearance

Not applicable — this is a server-side monitor-cycle composition function, not a visual component.

## States

Not applicable — this is a server-side monitor-cycle composition function, not a visual component; its runtime states (probe-only tick vs. full sync, in-progress vs. settled) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side monitor-cycle composition function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-cycle-runner-001 | skip-deploys-mirrors-full-sync, full-sync-phase-requires-success | `await runMonitorCycle(storage, { fullSync: false, config: testConfig() })` against a freshly migrated in-memory DB with `HEARTBEAT_URL` set and `fetch` stubbed to record every call | `runCycle` receives `{ skipDeploys: true }`; no call recorded against the heartbeat URL — `heartbeat.int.test.ts` › "pings after a successful FULL sync, not on probe-only ticks" (first half) |
| status-server-monitor-cycle-runner-002 | skip-deploys-mirrors-full-sync, full-sync-phase-requires-success, full-sync-phase-sequential-order, heartbeat-last, runs-core-sweep-first | `await runMonitorCycle(storage, { fullSync: true, config: testConfig() })` against the same DB, same `fetch` stub | `runCycle` receives `{ skipDeploys: false }`; exactly one call recorded against the heartbeat URL — `heartbeat.int.test.ts` › "pings after a successful FULL sync, not on probe-only ticks" (second half) |
| status-server-monitor-cycle-runner-003 | core-sweep-failure-propagates, full-sync-phase-requires-success | `await runMonitorCycle(storage, { fullSync: true, config: testConfig() })` against an un-migrated `Db` (so the cycle's first read throws inside `runCycle`) | The returned promise rejects (`rejects.toThrow()`); zero calls recorded against the heartbeat URL — `heartbeat.int.test.ts` › "does NOT ping when the sync fails" |
| status-server-monitor-cycle-runner-004 | alerts-flushed-every-call | `runCycle` stubbed to reject with `new Error('boom')`; `notifyIssueAlert({...})` called once beforehand; `config.alertWebhookUrl` set to a live URL; `await runMonitorCycle(storage, { fullSync: true, config })` | Exactly one webhook POST is delivered by the `finally` block's `flushAlerts` call before the returned promise itself rejects with `'boom'` — traced to the `try { await runCycle(...) } finally { await flushAlerts(...) }` structure in the source |
| status-server-monitor-cycle-runner-005 | maintenance-prune-logged-on-deletion | `storage.maintenance.runMaintenance` stubbed to resolve `{ deleted: 42, done: true }`; full sync run to completion | `console.log` is called with exactly `[maintenance] pruned 42 retention rows` (no suffix) |
| status-server-monitor-cycle-runner-006 | maintenance-prune-logged-on-deletion | `storage.maintenance.runMaintenance` stubbed to resolve `{ deleted: 100000, done: false }`; full sync run to completion | `console.log` is called with exactly `[maintenance] pruned 100000 retention rows — more next cycle` |
| status-server-monitor-cycle-runner-007 | maintenance-prune-logged-on-deletion | `storage.maintenance.runMaintenance` stubbed to resolve `{ deleted: 0, done: true }`; full sync run to completion | `console.log` is never called with a `[maintenance]`-prefixed message |
| status-server-monitor-cycle-runner-008 | maintenance-phase-failure-aborts-remainder, full-sync-phase-sequential-order | `storage.maintenance.runMaintenance` stubbed to reject with `new Error('disk full')`; `storage.maintenance.snapshotIfDue` and `pingHeartbeat`'s underlying `fetch` both spied; `await runMonitorCycle(storage, { fullSync: true, config })` | The returned promise rejects with `'disk full'`; `snapshotIfDue` is never called; no call is recorded against the heartbeat URL |
| status-server-monitor-cycle-runner-009 | config-threaded-unchanged | `config.alertWebhookUrl = 'https://hooks.example/x'`, `config.heartbeatUrl = null`; `runCycle` and `collectTelemetry` spied; full sync run to completion | `runCycle` and `collectTelemetry` are each called with the identical `config` object reference (`===`) passed into `runMonitorCycle`; `flushAlerts` is called with exactly `'https://hooks.example/x'`; `pingHeartbeat` is called with exactly `null` (still invoked — the null check is `pingHeartbeat`'s own no-op, not a call this file skips) |
| status-server-monitor-cycle-runner-010 | maintenance-uses-store-defaults | `storage.maintenance.runMaintenance` and `storage.maintenance.snapshotIfDue` both spied; full sync run to completion | Both spies are recorded as called with zero arguments |
| status-server-monitor-cycle-runner-011 | resolves-void-on-success | Every collaborator (`runCycle`, `fetchPeers`, `collectTelemetry`, `storage.maintenance.*`, `pingHeartbeat`, `flushAlerts`) stubbed to resolve; `await runMonitorCycle(storage, { fullSync: true, config })` | The awaited expression evaluates to `undefined`; no thrown error |
| status-server-monitor-cycle-runner-012 | no-connection-lifecycle-management | Static read of `cycle-runner.ts`'s import list | The file imports no connection-opening symbol (no `openLibsql`, no `LibsqlConnection`, no `createLibsqlStorage`) — every import is either a type (`StatusConfig`, `Storage`) or a collaborator function (`runCycle`, `fetchPeers`, `collectTelemetry`, `pingHeartbeat`, `flushAlerts`) |

## Edge Cases

- **Null and empty input**: `config.heartbeatUrl` of `null` MUST NOT stop `runMonitorCycle` from calling `pingHeartbeat(null)` on a full sync — the call still happens every full sync; the no-op is `pingHeartbeat`'s own contract, not a branch in this file. `config.alertWebhookUrl` of `null` MUST NOT stop `runMonitorCycle` from calling `flushAlerts(null)` every cycle (inside every `finally`, full sync or not) — again, the resulting no-op and left-queued alerts are `flushAlerts`'s own contract. An empty active-peer roster (`storage.peers.listActive()` resolving `[]`) MUST let `fetchPeers`'s internal `Promise.all([])` resolve immediately, so `runMonitorCycle` proceeds straight to `collectTelemetry` with no added delay.
- **Boundary values**: `opts.fullSync` has exactly two values; there is no partial or intermediate sync mode this file recognizes — MUST. `runMaintenance`'s own row budget (100,000 rows per call, in the `MaintenanceStore` implementation, external to this file) is never overridden here; when a backlog exceeds it, `runMaintenance` resolves `{ done: false }`, this file logs the "more next cycle" suffix (maintenance-prune-logged-on-deletion), and proceeds unconditionally to `snapshotIfDue` and `pingHeartbeat` in the same cycle — it does not loop or re-invoke `runMaintenance` itself within one `runMonitorCycle` call — MUST.
- **Concurrent access**: `runMonitorCycle` installs no mutex, lock, or reentrancy guard of its own; nothing in this file prevents two concurrent calls against the same `storage` from interleaving their steps. Serialization is delegated entirely to callers external to this file: the API-thread scheduler's single-flight `tick()` (`scheduler.ts`, which never starts a new cycle while `inFlight` is `true`) and the fact that the monitor `Worker` thread (`worker.ts`) processes one `CycleRequest` message handler invocation at a time. This file's own guarantee is limited to the sequential ordering of its own steps within one call (full-sync-phase-sequential-order) — MUST NOT be read as a promise that concurrent calls are serialized.
- **Error states**: a `runCycle` rejection propagates after `flushAlerts` runs, and the full-sync phase never starts for that cycle — MUST (core-sweep-failure-propagates). A `storage.maintenance.runMaintenance()` rejection propagates and aborts `snapshotIfDue`/`pingHeartbeat` for that cycle — MUST (maintenance-phase-failure-aborts-remainder). `fetchPeers`, `collectTelemetry`, `storage.maintenance.snapshotIfDue`, `pingHeartbeat`, and `flushAlerts` are each documented fail-soft by their own module (they catch and log internally and never reject) — this file installs no additional `try`/`catch` around any of them and relies entirely on each one's own contract; if one of them were to throw contrary to its documented contract, that throw would propagate through this file exactly like a `runMaintenance` failure does — MUST.
- **Offline / disconnected state**: loss of connectivity to the heartbeat check-in URL or the alert webhook mid-cycle is absorbed entirely by `pingHeartbeat`'s and `flushAlerts`'s own 5,000ms timeout-plus-catch (both external to this file); this file neither times out nor retries either call itself. Loss of connectivity to a peer, to GlitchTip, or to PostHog is absorbed by `fetchPeers`'s and `collectTelemetry`'s own per-item `try`/`catch` (external), recorded as unreachable rather than aborting the cycle. Loss of the storage connection itself (the underlying libSQL/SQLite file becoming unreachable mid-cycle) is not specially handled by this file at all: any `storage` call that throws surfaces exactly like the `runCycle`/`runMaintenance` failures above — propagate, abort whatever of the full-sync phase had not yet started — MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` (parameter) | `Storage` | none — caller-supplied, required | The persistence port every collaborator reads/writes through. The connection it wraps is opened and owned by the caller (`index.ts` on the API thread, `worker.ts` on the monitor worker thread) — this file never opens, closes, or tunes it. |
| `opts.fullSync` (parameter) | `boolean` | none — caller-supplied, required | `true` runs the full cycle (probe plus deploys/peers/telemetry/maintenance/heartbeat); `false` runs the cheap probe-only tick (`skipDeploys: true` into `runCycle`, and the entire full-sync-only phase skipped). The cadence that decides which value to pass on each tick lives in the scheduler wiring (`index.ts`, `scheduler.ts`), external to this file. |
| `opts.config` (parameter) | `StatusConfig` | none — caller-supplied, required | Threaded unchanged into `runCycle` and `collectTelemetry`. This file itself reads exactly two of its fields directly: `config.alertWebhookUrl` (passed to `flushAlerts`) and `config.heartbeatUrl` (passed to `pingHeartbeat`). |
| `storage.maintenance.runMaintenance` budget | `{ maxRows?: number; chunkRows?: number }` | `maxRows: 100_000`, `chunkRows: 25_000` (set inside `MaintenanceStore`, external) | This file calls `runMaintenance()` with no arguments, so the `MaintenanceStore` implementation's own defaults always apply (maintenance-uses-store-defaults). |
| `storage.maintenance.snapshotIfDue` options | `SnapshotOptions` (`dbUrl?`, `intervalMs?`, `keep?`, `now?`) | 24h interval, keep 7, adapter's own connection URL (set inside `MaintenanceStore`, external) | This file calls `snapshotIfDue()` with no arguments, so the implementation's own defaults always apply (maintenance-uses-store-defaults). |
| `HEARTBEAT_URL` / `config.heartbeatUrl` | `string \| null`, read by `config/env.ts` (external) into `StatusConfig.heartbeatUrl` | unset → `null` | `null` disables the dead-man ping for the whole process; this file still calls `pingHeartbeat(null)` every full sync, and the no-op happens inside `pingHeartbeat`. |
| `ALERT_WEBHOOK_URL` / `config.alertWebhookUrl` | `string \| null`, read by `config/env.ts` (external) into `StatusConfig.alertWebhookUrl` | unset → `null` | `null` disables webhook alert delivery for the whole process; this file still calls `flushAlerts(null)` every cycle, and the no-op (queue left intact) happens inside `flushAlerts`. |

## Deep Linking

Not applicable: this file defines no application URL scheme or HTTP route of its own — `config.heartbeatUrl` and `config.alertWebhookUrl` are outbound destinations it is handed and calls out to, not deep-link targets it defines or resolves.

## Localization

This file's only literal string is the hardcoded English `console.log` message it builds for a retention prune (maintenance-prune-logged-on-deletion). It routes through no localization mechanism, and unlike the Slack/Discord-rendered lines in `alerts.ts` (see the [Status Server Monitor Alerts](agentictoolkit://recipes/status-server-monitor-alerts) recipe), this string's only audience is an operator reading container stdout, never an end user or a webhook receiver.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `[maintenance] pruned <deleted> retention rows` | `console.log` after a full sync's `runMaintenance` call, when `deleted > 0` |
| n/a | ` — more next cycle` | Suffix appended to the line above when `runMaintenance`'s `done` flag is `false` |

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system. Its only on/off levers are `config.heartbeatUrl` and `config.alertWebhookUrl` each being `null` or not (documented under Configuration), and `opts.fullSync`, which is a caller-decided cadence value, not a flag lookup this file performs.

## Analytics

Not applicable: this file emits no analytics or usage-telemetry event describing its own execution. `collectTelemetry` polls GlitchTip/PostHog for data about the *monitored* fleet — it is not this file instrumenting itself.

## Privacy

- **Data collected**: this file directly reads two fields of `config` — `alertWebhookUrl` and `heartbeatUrl` — and threads the entire `config` value (including `config.credentials`, the provider API tokens) into `runCycle` and `collectTelemetry`. This file itself never inspects, transforms, or logs any credential value.
- **Storage**: none. `runMonitorCycle` holds no field and closes over no state between calls; every value it touches is either an argument or a value a collaborator resolved and handed back.
- **Transmission**: `config.heartbeatUrl` and `config.alertWebhookUrl` — each an opaque, potentially secret-bearing destination URL (a healthchecks.io-style check-in path or a Slack/Discord webhook path) — are the only two outbound destinations this file itself selects, by handing them to `pingHeartbeat`/`flushAlerts`. Neither URL, nor any credential from `config.credentials`, is ever written to this file's own `console.log` line.
- **Retention**: not applicable to this file directly — it holds no state between calls; retention of the underlying `health_checks`/`metrics_hourly`/`analytics_metrics`/`issues` rows is `runMaintenance`'s concern (external, documented in its own `MaintenanceStore` implementation), and this file only logs the row count that call reports.

## Logging

This file uses a plain `console.log` call with a literal `[maintenance]` string prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Retention prune deleted at least one row on a full sync | log (`console.log`) | `[maintenance] pruned <deleted> retention rows` (plus ` — more next cycle` when `done` is `false`) |

This is the only log line this file emits directly; a full sync whose prune deletes nothing produces no log output from this file at all, and a probe-only tick never reaches this line regardless of outcome.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this composition pattern models `runMonitorCycle` as an `async` function or an `actor` method taking a `Storage`-equivalent protocol and a `Sendable` `StatusConfig`-equivalent struct, using `defer` in place of `finally` to guarantee the alert flush runs whether the core sweep throws or not, and ordering the full-sync-only phase as a strict sequence of `await` calls (never `withThrowingTaskGroup`, which would let them run concurrently and defeat heartbeat-last).
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the function as a `suspend fun`, uses a `try`/`finally` block identical in shape to the source (Kotlin's `finally` has the same run-regardless-of-exception semantics as JavaScript's), and keeps the full-sync-only phase as sequential `suspend` calls on one coroutine rather than `async`/`awaitAll`, for the same heartbeat-last reason.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/cycle-runner.ts` as a plain exported `async function` on the Node status backend, imported by exactly two hosts external to this file: `monitor/worker.ts` (the monitor `Worker` thread's message handler) and the API-thread scheduler wiring re-exported from `index.ts`/built on `scheduler.ts`. It depends only on plain JavaScript `try`/`finally` and `Promise` sequencing — no framework of its own.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern would typically run it from a background `Task` rather than a separate OS thread/process the way Node's `Worker` isolates it here; the "why a worker thread" rationale in `worker.ts`'s header comment (keeping the API event loop responsive) has no direct AppKit/UIKit analogue unless the host app also multiplexes a UI event loop with this work, in which case the same off-main-thread `Task` applies.
- **WinUI 3**: a .NET port models `runMonitorCycle` as `async Task RunMonitorCycleAsync(IStorage storage, bool fullSync, StatusConfig config)`, using `try`/`finally` (identical run-regardless-of-exception semantics to the source) around the `RunCycleAsync` call to guarantee `FlushAlertsAsync` runs, and a strict sequence of `await`-ed calls (`FetchPeersAsync`, `CollectTelemetryAsync`, `IMaintenanceStore.RunMaintenanceAsync`, `IMaintenanceStore.SnapshotIfDueAsync`, `PingHeartbeatAsync`) for the full-sync-only phase — never `Task.WhenAll`, which would break heartbeat-last. The `console.log` line becomes an `ILogger.LogInformation` call with the same conditional-suffix message. `ObservableCollection`/`INotifyPropertyChanged` do not apply to this file: it has no UI-bound state of its own to expose: those types belong to a WinUI 3 host's dashboard view model consuming this cycle's results, not to the cycle composition itself.

## Design Decisions

- **Decision**: flush alerts in a `finally` around only the `runCycle` call, not around the whole full-sync phase.
  **Rationale**: the source comment on the `finally` block states it directly — "Deliver whatever the recorders queued even when a later phase of the cycle throws — an outage alert must not be lost to an unrelated failure." Only `runCycle`'s outage-detecting sweep ever queues an alert via `notifyIssueAlert`; the full-sync-only phase has none of its own to protect, so its failures are deliberately left to propagate uncaught instead of being wrapped in the same guarantee.
  **Approved**: pending
- **Decision**: let a full-sync-phase failure (from `runMaintenance` or any earlier step) propagate all the way to `runMonitorCycle`'s caller instead of catching it locally.
  **Rationale**: `heartbeat.ts`'s own header comment states the dead-man design directly — "a failing or wedged monitor stops pinging, and the external service... raises the alert no in-container code could." Catching the error here and continuing to `pingHeartbeat` would report success on a full sync that never actually completed, defeating that external detection path.
  **Approved**: pending
- **Decision**: call `runMaintenance()` and `snapshotIfDue()` with their default options rather than supplying explicit budgets from this file.
  **Rationale**: the row budget, chunk size, snapshot interval, and keep-count all live inside the `MaintenanceStore` implementation (`libsql/stores/maintenance-store.ts`) specifically so every caller — this cycle and the `POST /cron/maintenance` route alike — shares one tuned policy; this file has no cycle-specific reason to diverge from it.
  **Approved**: pending
- **Decision**: run the full-sync-only phase as a strict sequence, never concurrently, with `pingHeartbeat` last.
  **Rationale**: ordering is what makes the heartbeat mean "the entire full sync, including maintenance and snapshotting, completed" — running the phase's steps concurrently (e.g. via `Promise.all`) would let a hung `collectTelemetry` race a `pingHeartbeat` that had already fired, defeating the dead-man design's stated purpose of only pinging on a fully successful sync.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |

`unit-test-coverage` is `partial`: `heartbeat.int.test.ts`'s "cycle-runner heartbeat wiring" suite exercises `runMonitorCycle` directly for the full-sync/probe-only gating and for failure-propagation (vectors 001-003), but no test file targets `cycle-runner.ts` for its own sake — the maintenance-logging behavior, the strict five-step ordering, and the config-threading facts (vectors 005-010, 012) are traceable to reading the source rather than to an existing assertion. `separation-of-concerns` passes: the file's own header comment states its role is to keep "the worker entry (`worker.ts`) pure glue," and it contains no business logic of its own — every decision (what to probe, how to alert, how to prune) lives in the collaborator it calls. `explicit-error-handling` passes: this file never swallows an error itself; `runCycle` and `runMaintenance` failures explicitly propagate (core-sweep-failure-propagates, maintenance-phase-failure-aborts-remainder), and every other collaborator's fail-soft contract is documented in that collaborator's own module. `error-recovery` passes: a failed cycle does not crash the host process — the caller (`scheduler.ts`'s `tick()`, external) catches and logs the rejection and retries on the next tick, while each collaborator this file depends on recovers transiently-failing calls (a peer, a provider, a webhook) independently. `graceful-degradation` passes: every optional dependency this file's collaborators reach — the peer roster, GlitchTip, PostHog, the heartbeat URL, the alert webhook — degrades to a no-op or a recorded-unreachable state rather than aborting the cycle when unset or unreachable. `health-observability` passes: the `[maintenance]` log line and the heartbeat ping are exactly the external-facing health signals this check calls for in a long-running background process. `idempotent-operations` passes: every write this file triggers on a retried (next-cycle) run is documented idempotent or non-duplicating by its own module — `rollupMetrics`-driven upserts, cutoff-keyed chunked pruning, an interval-gated snapshot, and a ping/flush that simply repeat with no side effect from repetition.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
