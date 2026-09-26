---
id: 5cb60b95-0a8b-43c8-a747-cb5ca7353f09
title: Status Server Monitor Worker
domain: agentictoolkit://cookbook/status-server/monitor/worker
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Thread entry for the monitor worker: boots one DB connection and cooldown registry, then relays each CycleRequest to runMonitorCycle.'
platforms:
- typescript
- web
tags:
- monitor
- worker
- concurrency
- database
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/concurrency/concurrency
- agenticdevelopercookbook://guidelines/implementing/data/database
- agenticdevelopercookbook://guidelines/implementing/data/transactions-and-concurrency
- agenticdevelopercookbook://guidelines/implementing/security/sensitive-data
- agenticdevelopercookbook://guidelines/implementing/observability/logging
- agenticdevelopercookbook://guidelines/implementing/code-quality/dependency-injection
related:
- agentictoolkit://cookbook/status-server/monitor/cycle-runner
- agentictoolkit://cookbook/status-server/libsql
references:
- packages/web/packages/status-server/src/monitor/worker.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/worker-client.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/cycle-runner.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/client.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/index.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/cooldown/provider-cooldown.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/status-server/test/worker-boot.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/helpers/worker-boot-driver.mjs (agentictoolkit)
- packages/web/packages/status-server/test/provider-cooldown-shared.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Worker

## Overview

`worker.ts` (`packages/web/packages/status-server/src/monitor/worker.ts`) is the entire body of the monitor `worker_threads` entry point — the module a `Worker` instance runs when `MonitorWorkerClient.spawn` (`worker-client.ts`) constructs it. Its own header comment states its purpose directly: "runs the ENTIRE monitoring cycle on its own thread — its own event loop, its own DB connection — so the heavy full-sync phase (four provider APIs, telemetry, TLS handshakes, JSON parsing) can never starve the API server's event loop again," naming the exact production incident this design fixes: starvation that "reset in-flight `/auth/me` and `/auth/refresh` proxy sockets (rendering the site signed-out) and made the supervisor's `/health` probes read 'down' and restart the container." The file itself is glue only, by explicit design: "the cycle logic lives in `cycle-runner.ts`; spawn/respawn/timeout policy lives in `worker-client.ts`." Its own contract is narrow: validate the `workerData` it was constructed with, open and tune one database connection, adopt the cross-thread provider-cooldown registry, build one `Storage` port, and then answer every `CycleRequest` message it receives by running `runMonitorCycle` and posting back a `CycleReply`.

## Behavioral Requirements

### Boot Preconditions

- **worker-thread-required**: The module MUST throw an `Error` with the message `monitor worker must be spawned via worker_threads (see worker-client.ts)` synchronously, during module evaluation, when `parentPort` is `null`.
- **connection-url-required**: The module MUST throw an `Error` with the message `monitor worker spawned without workerData.db.url (see MonitorWorkerData)` when `workerData` is `null`/`undefined`, or `workerData.db` is `null`/`undefined`, or `workerData.db.url` is falsy.
- **config-required**: The module MUST throw an `Error` with the message `monitor worker spawned without workerData.config (see MonitorWorkerData)` when `workerData.config` is falsy.
- **boot-checks-run-in-order**: The module MUST evaluate the `parentPort` check, then the `db.url` check, then the `config` check, in that exact order, and MUST NOT call `openLibsql` until all three checks have passed.
- **migrations-not-run-here**: The module MUST NOT run database migrations itself; it treats the schema as already migrated by the host's main thread before this worker was spawned, per its own comment: "Migrations already ran on the main thread before this worker was spawned."

### Connection Lifecycle

- **connection-opened-once**: The module MUST call `openLibsql(conn)` exactly once per worker instance, at module-evaluation time, after the boot preconditions pass and before attaching any `message` listener.
- **concurrency-tuning-applied-once**: The module MUST `await tuneDbForConcurrency(db, conn)` exactly once, immediately after `openLibsql`, before constructing storage or attaching the `message` listener.
- **storage-built-once-reused**: The module MUST call `createLibsqlStorage(db, conn)` exactly once and MUST reuse the resulting `Storage` value for every `CycleRequest` this worker instance receives; it MUST NOT rebuild storage per message.
- **no-explicit-close**: The module MUST NOT explicitly close, checkpoint, or otherwise release the connection it opened; the connection's lifetime is bound to the worker thread's own lifetime.

### Cooldown Adoption

- **cooldowns-attached-before-listening**: The module MUST call `attachCooldownState(cooldowns)` with the `cooldowns` field read from `workerData`, and MUST do so before attaching the `message` listener.
- **cooldowns-optional**: When `workerData.cooldowns` is `undefined`, the module MUST proceed without throwing; `attachCooldownState`'s own guard (`if (buffer) slots = new BigInt64Array(buffer)`) leaves the module's private, thread-local cooldown registry in place rather than blocking startup.

### Message Protocol

- **one-listener-registered**: The module MUST register exactly one `message` listener on `parentPort`, once, after connection setup and cooldown adoption complete.
- **reply-echoes-seq**: For every `CycleRequest` message received, the module MUST post back exactly one `CycleReply` whose `seq` field equals the received message's `seq` field, unchanged.
- **fullsync-passed-through**: The module MUST pass the received message's `fullSync` field, unchanged, as `runMonitorCycle`'s `opts.fullSync` argument.
- **storage-and-config-passed-unchanged**: The module MUST pass the single shared `storage` value built at boot as `runMonitorCycle`'s first argument, and MUST pass the `config` value captured from `workerData` at boot, unchanged, as `opts.config`, for every `CycleRequest` the worker processes.
- **success-reply-shape**: When the `runMonitorCycle` call resolves, the module MUST post back `{ seq, ok: true }` with no `error` field.
- **failure-reply-shape**: When the `runMonitorCycle` call rejects, the module MUST post back `{ seq, ok: false, error }`, where `error` is the rejection value's `message` property when that value is an `Error` instance, and `String(err)` otherwise.
- **cycle-failure-does-not-crash-worker**: A rejected `runMonitorCycle` call MUST NOT cause the module to throw, exit, or stop listening for further `message` events; the worker MUST remain able to process a subsequent `CycleRequest` after replying `{ ok: false }` to a failed one.

### Credential Handling

- **credentials-held-in-memory-only**: The module MUST hold `conn.authToken` and every field of `config` — including `config.credentials` and `config.secrets` — only in module-scope bindings (`conn`, `config`) for the lifetime of the worker thread; it MUST NOT write any of these values to disk, to a log call, or to a `CycleReply`.
- **credentials-cross-once-via-workerdata**: The module MUST obtain `conn` and `config` exclusively from the single destructure of `workerData` performed at module evaluation; it MUST NOT request, fetch, or otherwise read either value through any other channel while the worker is running.

## Appearance

Not applicable — this is a background `worker_threads` entry point, not a visual component.

## States

Not applicable — this is a background `worker_threads` entry point, not a visual component; its runtime states (unbooted, booted-and-idle, mid-cycle, crashed-at-boot) are captured under Behavioral Requirements and Edge Cases, not a visual-state table.

## Accessibility

Not applicable — this is a background `worker_threads` entry point, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-worker-001 | worker-thread-required | The module is loaded in a context where `parentPort` is `null` (not spawned as a `worker_threads` `Worker`) | Throws synchronously with message `monitor worker must be spawned via worker_threads (see worker-client.ts)` — traced to `if (!port) throw new Error(...)` |
| status-server-monitor-worker-002 | connection-url-required, boot-checks-run-in-order | Spawned with `workerData: { config: testConfig() }` (no `db` field) | Throws `monitor worker spawned without workerData.db.url (see MonitorWorkerData)` before any call to `openLibsql` |
| status-server-monitor-worker-003 | config-required, boot-checks-run-in-order | Spawned with `workerData: { db: { url: 'file::memory:' } }` (no `config` field) | Throws `monitor worker spawned without workerData.config (see MonitorWorkerData)` before any call to `openLibsql` |
| status-server-monitor-worker-004 | reply-echoes-seq, success-reply-shape, fullsync-passed-through, storage-and-config-passed-unchanged | The built worker entry is spawned via `worker-boot-driver.mjs` against a freshly migrated `file:` DB, then posted `{ seq: 1, fullSync: false }` | `worker-boot.int.test.ts` › "completes a cycle round-trip via the package-resolved worker entry": the driver's stdout carries a `REPLY:` line whose JSON is `{ "seq": 1, "ok": true }` |
| status-server-monitor-worker-005 | failure-reply-shape, cycle-failure-does-not-crash-worker | The worker is spawned against a `Db` whose schema was never migrated (so the first storage read inside `runMonitorCycle` throws), one `CycleRequest` is posted, then a second `CycleRequest` is posted to the same live worker instance | The first reply is `{ seq, ok: false, error: <message text> }`; the worker does not exit — the second `CycleRequest` still receives a reply — traced to the `try`/`catch` around `runMonitorCycle` in the `message` handler |
| status-server-monitor-worker-006 | cooldowns-optional | The worker is spawned with `workerData` omitting the `cooldowns` field entirely, exactly as `worker-boot-driver.mjs` constructs it (`{ db: { url }, config: envConfig(process.env) }`, no `cooldowns` key) | The worker boots and completes a cycle without throwing — traced to `attachCooldownState`'s own `if (buffer)` guard in `provider-cooldown.ts` |
| status-server-monitor-worker-007 | storage-built-once-reused | Two sequential `CycleRequest` messages (`seq: 1`, then `seq: 2`), both `fullSync: false`, are posted to the same live worker instance | Both receive a reply; a static read of the source shows `createLibsqlStorage` called exactly once, at module top level, never inside the `message` handler |
| status-server-monitor-worker-008 | no-explicit-close | Static read of the full body of `worker.ts` | No call to any connection-closing or checkpoint function (no `close`, no `checkpointWal`) appears anywhere in the file |
| status-server-monitor-worker-009 | migrations-not-run-here | Static read of `worker.ts`'s import list | `migrateDb` is not imported; the only `libsql`/`client` imports are `openLibsql`, `tuneDbForConcurrency`, and the `LibsqlConnection` type |
| status-server-monitor-worker-010 | credentials-held-in-memory-only | Static read of the full body of `worker.ts` for any statement referencing `conn`, `config`, `authToken`, `credentials`, or `secrets` | Those identifiers appear only as arguments passed to `openLibsql`, `tuneDbForConcurrency`, `createLibsqlStorage`, and `runMonitorCycle`; no `console.*` call and no `port.postMessage` call anywhere in the file references any of them |
| status-server-monitor-worker-011 | connection-opened-once, concurrency-tuning-applied-once | Static read of the source's statement order | `openLibsql` and `await tuneDbForConcurrency` each appear exactly once, both above the `port.on("message", ...)` call, in that order |
| status-server-monitor-worker-012 | cooldowns-attached-before-listening, one-listener-registered | Static read of the source's statement order | `attachCooldownState(cooldowns)` appears above the single `port.on("message", ...)` call; `port.on("message", ...)` appears exactly once in the file |
| status-server-monitor-worker-013 | credentials-cross-once-via-workerdata | Static read of the source's body for every occurrence of the identifier `workerData` | `workerData` is read exactly once, in the destructuring statement `const { db: conn, config, cooldowns } = (workerData ?? {}) as Partial<MonitorWorkerData<LibsqlConnection>>;` — no other statement in the file references `workerData` |
| status-server-monitor-worker-014 | cycle-failure-does-not-crash-worker | `runMonitorCycle` stubbed to reject with a plain (non-`Error`) thrown value, e.g. the string `'boom'` | The posted `CycleReply` has `error: 'boom'` (the `String(err)` branch, not `err.message`), matching `err instanceof Error ? err.message : String(err)` |
| status-server-monitor-worker-015 | boot-checks-run-in-order, connection-url-required | Spawned with `workerData: {}` (neither `db` nor `config` present) | Throws `monitor worker spawned without workerData.db.url (see MonitorWorkerData)` — the `db.url` check fires before the `config` check ever runs |

## Edge Cases

- **Null and empty input**: `workerData` of `null` or `undefined` is coerced to `{}` by `(workerData ?? {})`, so `conn` is `undefined`, `conn?.url` is `undefined`, and the module throws the `db.url` error — MUST. `workerData.db.url` of `""` is equally falsy and produces the same throw — MUST. `workerData.cooldowns` of `undefined` MUST NOT stop startup (cooldowns-optional).
- **Boundary values**: `msg.fullSync` has exactly two meaningful values (`true`/`false`); this file recognizes no partial or intermediate sync mode, passing whichever value it received straight through — MUST. `msg.seq` is a caller-assigned number with no range or uniqueness check performed by this file; whatever value the caller sends is echoed back unchanged in the reply — MUST.
- **Concurrent access**: nothing in this file prevents a second `message` event from starting a new `runMonitorCycle` call before an earlier one's promise has settled — each `message` event spawns its own `void (async () => { ... })()` invocation, and the handler function itself returns before that invocation's first `await`. If a caller ever posted a second `CycleRequest` before the first's `CycleReply` arrived, both cycles would execute against the same shared `storage`/`db` concurrently — this file installs no queue, lock, or single-flight guard of its own — MUST NOT be read as this file providing serialization. In normal operation this never happens because the only spawner in this codebase, `MonitorWorkerClient.runCycle`, and the scheduler's own single-flight `tick()` (both external to this file) keep at most one `CycleRequest` outstanding at a time.
- **Error states**: a `runMonitorCycle` rejection inside the `message` handler's `try`/`catch` is reported via `{ ok: false, error }` and the worker keeps running — MUST (cycle-failure-does-not-crash-worker). A failure during the boot sequence itself — a thrown boot-precondition check, or a rejection from `openLibsql`/`tuneDbForConcurrency` — happens before the `message` listener is ever attached, so it is an uncaught exception during module evaluation; Node's `worker_threads` semantics propagate this to the parent as the `Worker`'s `'error'` event (handled by `MonitorWorkerClient`'s `failAll`, external to this file), and the worker thread does not survive to answer any `CycleRequest` — MUST.
- **Offline / disconnected state**: for a remote libsql/Turso `conn.url` (not `file:`), `tuneDbForConcurrency`'s own `isEmbeddedFile` guard skips every `PRAGMA` call, so a network problem never surfaces at that `await` — MUST NOT run pragma tuning for a non-`file:` URL. A remote-connection failure that instead surfaces later — inside `runMonitorCycle`, on the first real query of a cycle — is caught by the `message` handler's `try`/`catch` and reported as an ordinary failed cycle (`ok: false`), exactly like any other cycle failure — MUST. This file performs no reconnection or retry of its own; recovery, if any, happens on the next `CycleRequest` this worker instance receives, or in a freshly spawned worker after a client-driven respawn, both external to this file.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workerData.db` | `LibsqlConnection` (`{ url: string; authToken?: string }`) | none — required | Connection descriptor handed to the `Worker` at construction. `url` MUST be a non-empty string or the module throws at boot (connection-url-required). |
| `workerData.config` | `StatusConfig` | none — required | Threaded unchanged into `runMonitorCycle` for every `CycleRequest` this worker instance processes (storage-and-config-passed-unchanged). |
| `workerData.cooldowns` | `SharedArrayBuffer \| undefined` | `undefined` → private, thread-local registry | Adopted via `attachCooldownState`. When supplied by the spawner (`MonitorWorkerClient.spawn`, external), this worker shares the same provider-cooldown state as whichever thread supplied it. |
| `CycleRequest.seq` (per message) | `number` | none — caller-assigned | Echoed back unchanged in the `CycleReply`; this file assigns it no meaning beyond matching a reply to its request. |
| `CycleRequest.fullSync` (per message) | `boolean` | none — caller-supplied | Passed unchanged as `runMonitorCycle`'s `opts.fullSync`. |

## Deep Linking

Not applicable: this file defines no application URL scheme or HTTP route; it is a `worker_threads` module entry reached only by `new Worker(...)` (in `worker-client.ts`), never a navigable link.

## Localization

This file's only string literals are three hardcoded English `Error` messages, each thrown at boot for a caller-misconfiguration condition, and each written for the developer/operator reading a crash log rather than for an end user — they route through no localization mechanism and are never displayed in any UI. The `CycleReply.error` string a failed cycle carries is not authored by this file either; it is whatever the rejected `runMonitorCycle` call's own error produced, passed through via `err.message`/`String(err)` unchanged.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `monitor worker must be spawned via worker_threads (see worker-client.ts)` | Thrown at boot when `parentPort` is `null` |
| n/a | `monitor worker spawned without workerData.db.url (see MonitorWorkerData)` | Thrown at boot when `workerData.db.url` is falsy |
| n/a | `monitor worker spawned without workerData.config (see MonitorWorkerData)` | Thrown at boot when `workerData.config` is falsy |

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; its only on/off lever is whether `workerData.cooldowns` was supplied (documented under Configuration), which is a spawn-time argument, not a flag lookup this file performs.

## Analytics

Not applicable: this file emits no analytics or usage-telemetry event describing its own execution. `collectTelemetry`, reached only indirectly through `runMonitorCycle`, polls GlitchTip/PostHog for data about the *monitored* fleet — it is not this file instrumenting itself.

## Privacy

- **Data collected**: this file's boot-time destructure of `workerData` reads `conn` (`url`, optionally `authToken`) and the entire `config` value, including `config.credentials` (the named provider API tokens) and `config.secrets` (the host's raw environment passthrough). This file itself never inspects or transforms any of these values beyond passing them to `openLibsql`, `tuneDbForConcurrency`, and `runMonitorCycle`.
- **Storage**: none written to disk by this file. `conn` and `config` are held only in module-scope bindings for the lifetime of the worker thread — longer-lived than a single `CycleRequest`, but never persisted beyond the thread's own process memory.
- **Transmission**: `conn` and `config` cross into this thread exactly once, via the structured-clone `workerData` transfer Node performs when `worker-client.ts` constructs the `Worker` — an in-process transfer, not a network call this file makes. This file never re-transmits either value; the only outbound message it sends is a `CycleReply`, whose only string content is `seq`, `ok`, and — on failure — an `error` message. That `error` string is relayed verbatim from whatever the rejected `runMonitorCycle` call produced; this file performs no redaction of it, so whether a lower-layer failure (inside the libSQL driver `openLibsql`/`tuneDbForConcurrency` use, or inside a provider fetch reached through `runMonitorCycle`) could embed a credential in its own `Error.message` is a property of those external modules, not of this file.
- **Retention**: not applicable to this file directly in the sense of a data store — `conn`/`config`/`db`/`storage` are held for as long as the worker thread lives (until the client terminates it), and disappear entirely when the thread exits; this file retains nothing across worker respawns.

## Logging

This file itself contains no `console.*` call and defines no logger of its own — none of the three boot-time `Error` messages are separately logged here; they propagate as thrown exceptions (see Error states). A cycle failure is communicated only through the `CycleReply.error` field, not a log line from this file. Running a cycle on this thread can indirectly cause a log line from a collaborator external to this file — `runMonitorCycle`'s own `[maintenance]` line (`cycle-runner.ts`) on a full sync, and `provider-cooldown.ts`'s `console.error` `[cooldown] ...` line if a provider fetch reached through this cycle hits a 429 — but neither line is emitted by `worker.ts` itself.

| Event | Level | Message |
|-------|-------|---------|
| n/a — this file emits no log line of its own | n/a | n/a |

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion process embedding this pattern models the worker boundary as a background `Task` or a dedicated `DispatchQueue`/`Thread` rather than a JS `worker_threads` `Worker`, since Swift concurrency does not need a second OS thread purely to protect an event loop the way Node does; the boot-precondition throws become preconditions checked once when that background context starts, and the DB connection (`Db`-equivalent) is opened and tuned once, then held for that context's lifetime exactly as here.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port runs the equivalent of this file's setup inside a dedicated `CoroutineScope` bound to a background dispatcher, opening and tuning its own database connection/coroutine-safe client once at scope creation, then handling each cycle request as a `suspend fun` call inside a `Channel`/`Flow` collector standing in for the `message` listener — with the same lack of built-in single-flight serialization this file has, unless the port deliberately adds it.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/worker.ts`, a Node `worker_threads` entry module resolved through this package's own `exports` map (`worker-client.ts`'s `MonitorWorkerClient.spawn`) rather than a relative import — `worker-boot.int.test.ts` exists specifically to regression-guard that resolution path under bare `node`. It depends on `node:worker_threads`'s `parentPort`/`workerData`, on this package's own `../libsql/client` and `../libsql` modules, and on `@agentic-toolkit/deploy-platform/cooldown`'s `SharedArrayBuffer`-backed cross-thread state.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS host embedding this pattern would typically reach for a background `Task` rather than a second OS thread/process the way Node's `Worker` isolates it here; the "why a separate thread" rationale in this file's own header comment (keeping the API event loop responsive under heavy I/O) has no direct AppKit/UIKit analogue unless the host also multiplexes a UI run loop with this work.
- **WinUI 3**: a .NET port models this file as a dedicated background `Task` (or a long-running `System.Threading.Channels.Channel<T>` consumer) started once at process boot, never a UI-thread object. Boot preconditions become argument validation on that `Task`'s entry method, throwing `InvalidOperationException`/`ArgumentException` with the same three messages. The connection opens once via a `Microsoft.Data.Sqlite`/libSQL .NET client (`HttpClient` under the hood for a remote libsql/Turso endpoint), tuned once with the WAL/`busy_timeout` equivalents `System.Text.Json`-configured `StatusConfig`-equivalent record is captured once and passed unchanged into each cycle call. The `CycleRequest`/`CycleReply` message protocol becomes a `Channel<CycleRequest>`/`Channel<CycleReply>` pair (or a `TaskCompletionSource` per request) instead of `parentPort.postMessage`, awaited with the same fire-and-forget-per-request shape as this file's `void (async () => { ... })()`. `ObservableCollection`/`INotifyPropertyChanged` do not apply here: this file has no UI-bound state of its own to expose — those types belong to a WinUI 3 host's dashboard view model consuming a cycle's *results*, not to this worker boundary itself.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/worker.ts` |

## Design Decisions

- **Decision**: validate only that `workerData.db.url` and `workerData.config` are present/truthy at boot, not their full shape or validity.
  **Rationale**: the source's own comment states this narrowly, on purpose: "Fail fast on a malformed spawn rather than surfacing a confusing crash deep inside `openLibsql`/`runMonitorCycle`: `db`/`config` are the two things the client MUST supply (see `MonitorWorkerData`) and a missing one means the client itself is broken." A malformed-but-present value (a syntactically invalid URL, a config object missing an unrelated optional field) is deliberately left to surface later — inside `openLibsql`/`tuneDbForConcurrency` at boot, or inside a cycle's own `try`/`catch` — rather than this file attempting deeper validation of a shape `MonitorWorkerData`'s type already documents.
  **Approved**: pending
- **Decision**: fire-and-forget each cycle's async work from the `message` handler rather than queueing or awaiting a previous cycle before starting the next.
  **Rationale**: the only spawner of this module in this codebase, `MonitorWorkerClient`, never posts a second `CycleRequest` before the first's `CycleReply` arrives — the scheduler's own single-flight `tick()` (external, per the sibling Status Server Monitor Cycle Runner recipe's Concurrent Access analysis) keeps exactly one cycle outstanding system-wide. Adding a queue or lock here would duplicate a guarantee the caller already provides, for a condition this file never actually encounters in production.
  **Approved**: pending
- **Decision**: run the entire monitoring cycle on a dedicated worker thread, with its own DB connection, rather than in-process on the API thread.
  **Rationale**: the file's own header comment names the incident this fixes directly — heavy full-sync work (four provider APIs, telemetry, TLS handshakes, JSON parsing) starved the API server's event loop, resetting in-flight `/auth/me`/`/auth/refresh` proxy sockets and making `/health` probes read "down," which triggered supervisor container restarts. A dedicated thread with its own event loop and its own connection removes that starvation path entirely.
  **Approved**: pending
- **Decision**: deliver `conn`/`config` (including every credential they carry) exclusively through `worker_threads`' structured-clone `workerData`, never through any other channel this file reads from.
  **Rationale**: `workerData` crosses the thread boundary in-process, never serialized to a command-line argument (world-readable via `ps` for the life of the process) or to a network call. `worker-boot.int.test.ts`'s own driver (`worker-boot-driver.mjs`) delivers the equivalent payload over stdin rather than argv for exactly this reason, by its own comment: "a command-line argument is world-readable through `ps` for the life of the process, and would be echoed back into any error the test throws." This file's single `workerData` destructure is the only read of that boundary.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | partial | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | partial | Reliability |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | partial | Security |

`unit-test-coverage` is `partial`: `worker-boot.int.test.ts` exercises exactly one path end to end — a successful boot plus one `fullSync: false` cycle round-trip under bare `node`, guarding the package-`exports` resolution regression it was written for. No test in the given sources exercises the boot-precondition throws, a failed cycle's `error` shape, `cooldowns-optional`, or the storage-built-once-reused/no-explicit-close facts; those are traceable to reading the source (vectors 001-003, 005-013) rather than to an existing assertion. `separation-of-concerns` passes: the file's own header comment states its role is "glue only," and every decision it makes beyond boot validation and message relay — what a cycle does, how it fails soft, what it alerts on — lives in `cycle-runner.ts`, `openLibsql`/`tuneDbForConcurrency`, or `createLibsqlStorage`, all external to this file. `explicit-error-handling` passes: every failure this file can encounter either throws explicitly (the three boot checks) or is caught and reported explicitly (`failure-reply-shape`); nothing is swallowed. `error-recovery` passes for the file's primary contract — a per-cycle failure is reported and the worker keeps serving further requests without intervention — though a boot-time failure instead crashes the whole worker, recovered by `MonitorWorkerClient`'s respawn-on-next-call (external), which is why `graceful-degradation` is only `partial`: this file's per-cycle path degrades gracefully (`ok: false`, worker survives), but a bad connection discovered at boot is handled by failing fast and crashing, not by degrading — a deliberate, complementary strategy per the Design Decisions entry above, not a defect, but not "graceful" by this check's own wording either. `fault-tolerance` passes: the check's own linked guideline is `agenticdevelopercookbook://principles/fail-fast`, and this file's boot-time throws are exactly that pattern applied to a caller bug (a missing required field), which the guideline endorses rather than forbids; the file's per-message path never crashes on a malformed `CycleRequest` either, since a bad value is simply threaded through unchecked (documented under Configuration and Edge Cases) rather than causing a throw. `health-observability` is `partial`: this file itself emits no health signal of its own — the heartbeat ping and the `[maintenance]` log line both live in `runMonitorCycle`'s collaborators (external, see the Status Server Monitor Cycle Runner recipe); this file's only contribution is the `CycleReply.ok`/`error` fields, which a caller would still need to surface as a metric. `secure-log-output` is `partial`: this file's own three hardcoded strings and its `console.*`-free body contain no credential (passes on its own code), but the `CycleReply.error` string it relays is unredacted output from whatever a lower layer's `Error.message` contains, and this file makes no attempt to strip a credential that might appear there — a residual gap owned by the external modules named above, not fixed at this layer.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
