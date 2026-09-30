<!-- leaf: implement-status-server-monitor-1/cycle-runner · source: status-server-monitor-cycle-runner.md -->

**Rules** (cite as `implement-status-server-monitor-1/cycle-runner#<slug>`):

- `runs-core-sweep-first` MUST
- `skip-deploys-mirrors-full-sync` MUST
- `config-threaded-unchanged` MUST
- `no-connection-lifecycle-management` MUST
- `resolves-void-on-success` MUST
- `alerts-flushed-every-call` MUST
- `core-sweep-failure-propagates` MUST
- `full-sync-phase-requires-success` MUST
- `full-sync-phase-sequential-order` MUST
- `heartbeat-last` MUST
- `maintenance-phase-failure-aborts-remainder` MUST
- `maintenance-uses-store-defaults` MUST
- `maintenance-prune-logged-on-deletion` MUST

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

## Localization

This file's only literal string is the hardcoded English `console.log` message it builds for a retention prune (maintenance-prune-logged-on-deletion). It routes through no localization mechanism, and unlike the Slack/Discord-rendered lines in `alerts.ts` (see the Status Server Monitor Alerts recipe), this string's only audience is an operator reading container stdout, never an end user or a webhook receiver.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `[maintenance] pruned <deleted> retention rows` | `console.log` after a full sync's `runMaintenance` call, when `deleted > 0` |
| n/a | ` — more next cycle` | Suffix appended to the line above when `runMaintenance`'s `done` flag is `false` |

## Privacy

- **Data collected**: this file directly reads two fields of `config` — `alertWebhookUrl` and `heartbeatUrl` — and threads the entire `config` value (including `config.credentials`, the provider API tokens) into `runCycle` and `collectTelemetry`. This file itself never inspects, transforms, or logs any credential value.
- **Storage**: none. `runMonitorCycle` holds no field and closes over no state between calls; every value it touches is either an argument or a value a collaborator resolved and handed back.
- **Transmission**: `config.heartbeatUrl` and `config.alertWebhookUrl` — each an opaque, potentially secret-bearing destination URL (a healthchecks.io-style check-in path or a Slack/Discord webhook path) — are the only two outbound destinations this file itself selects, by handing them to `pingHeartbeat`/`flushAlerts`. Neither URL, nor any credential from `config.credentials`, is ever written to this file's own `console.log` line.
- **Retention**: not applicable to this file directly — it holds no state between calls; retention of the underlying `health_checks`/`metrics_hourly`/`analytics_metrics`/`issues` rows is `runMaintenance`'s concern (external, documented in its own `MaintenanceStore` implementation), and this file only logs the row count that call reports.

