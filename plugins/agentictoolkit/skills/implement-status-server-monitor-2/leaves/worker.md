<!-- leaf: implement-status-server-monitor-2/worker · source: status-server-monitor-worker.md -->

**Rules** (cite as `implement-status-server-monitor-2/worker#<slug>`):

- `worker-thread-required` MUST
- `connection-url-required` MUST
- `config-required` MUST
- `boot-checks-run-in-order` MUST
- `migrations-not-run-here` MUST
- `connection-opened-once` MUST
- `concurrency-tuning-applied-once` MUST
- `storage-built-once-reused` MUST
- `no-explicit-close` MUST
- `cooldowns-attached-before-listening` MUST
- `cooldowns-optional` MUST
- `one-listener-registered` MUST
- `reply-echoes-seq` MUST
- `fullsync-passed-through` MUST
- `storage-and-config-passed-unchanged` MUST
- `success-reply-shape` MUST
- `failure-reply-shape` MUST
- `cycle-failure-does-not-crash-worker` MUST
- `credentials-held-in-memory-only` MUST
- `credentials-cross-once-via-workerdata` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workerData.db` | `LibsqlConnection` (`{ url: string; authToken?: string }`) | none — required | Connection descriptor handed to the `Worker` at construction. `url` MUST be a non-empty string or the module throws at boot (connection-url-required). |
| `workerData.config` | `StatusConfig` | none — required | Threaded unchanged into `runMonitorCycle` for every `CycleRequest` this worker instance processes (storage-and-config-passed-unchanged). |
| `workerData.cooldowns` | `SharedArrayBuffer \| undefined` | `undefined` → private, thread-local registry | Adopted via `attachCooldownState`. When supplied by the spawner (`MonitorWorkerClient.spawn`, external), this worker shares the same provider-cooldown state as whichever thread supplied it. |
| `CycleRequest.seq` (per message) | `number` | none — caller-assigned | Echoed back unchanged in the `CycleReply`; this file assigns it no meaning beyond matching a reply to its request. |
| `CycleRequest.fullSync` (per message) | `boolean` | none — caller-supplied | Passed unchanged as `runMonitorCycle`'s `opts.fullSync`. |

## Localization

This file's only string literals are three hardcoded English `Error` messages, each thrown at boot for a caller-misconfiguration condition, and each written for the developer/operator reading a crash log rather than for an end user — they route through no localization mechanism and are never displayed in any UI. The `CycleReply.error` string a failed cycle carries is not authored by this file either; it is whatever the rejected `runMonitorCycle` call's own error produced, passed through via `err.message`/`String(err)` unchanged.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `monitor worker must be spawned via worker_threads (see worker-client.ts)` | Thrown at boot when `parentPort` is `null` |
| n/a | `monitor worker spawned without workerData.db.url (see MonitorWorkerData)` | Thrown at boot when `workerData.db.url` is falsy |
| n/a | `monitor worker spawned without workerData.config (see MonitorWorkerData)` | Thrown at boot when `workerData.config` is falsy |

## Privacy

- **Data collected**: this file's boot-time destructure of `workerData` reads `conn` (`url`, optionally `authToken`) and the entire `config` value, including `config.credentials` (the named provider API tokens) and `config.secrets` (the host's raw environment passthrough). This file itself never inspects or transforms any of these values beyond passing them to `openLibsql`, `tuneDbForConcurrency`, and `runMonitorCycle`.
- **Storage**: none written to disk by this file. `conn` and `config` are held only in module-scope bindings for the lifetime of the worker thread — longer-lived than a single `CycleRequest`, but never persisted beyond the thread's own process memory.
- **Transmission**: `conn` and `config` cross into this thread exactly once, via the structured-clone `workerData` transfer Node performs when `worker-client.ts` constructs the `Worker` — an in-process transfer, not a network call this file makes. This file never re-transmits either value; the only outbound message it sends is a `CycleReply`, whose only string content is `seq`, `ok`, and — on failure — an `error` message. That `error` string is relayed verbatim from whatever the rejected `runMonitorCycle` call produced; this file performs no redaction of it, so whether a lower-layer failure (inside the libSQL driver `openLibsql`/`tuneDbForConcurrency` use, or inside a provider fetch reached through `runMonitorCycle`) could embed a credential in its own `Error.message` is a property of those external modules, not of this file.
- **Retention**: not applicable to this file directly in the sense of a data store — `conn`/`config`/`db`/`storage` are held for as long as the worker thread lives (until the client terminates it), and disappear entirely when the thread exits; this file retains nothing across worker respawns.

