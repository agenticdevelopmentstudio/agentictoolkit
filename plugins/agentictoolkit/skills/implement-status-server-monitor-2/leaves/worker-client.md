<!-- leaf: implement-status-server-monitor-2/worker-client · source: status-server-monitor-worker-client.md -->

**Rules** (cite as `implement-status-server-monitor-2/worker-client#<slug>`):

- `generic-connection-parameter` MUST
- `constructor-injected-configuration` MUST
- `lazy-spawn-on-first-call` MUST
- `worker-entry-via-package-exports` MUST
- `cooldowns-attached-at-spawn` MUST
- `cooldown-buffer-shared-across-respawns` MUST
- `monotonic-sequence-numbers` MUST
- `single-request-per-call` MUST
- `cycle-timeout-rejection-message` MUST
- `timeout-terminates-and-clears-worker` MUST
- `reply-ok-resolves-void` MUST
- `reply-not-ok-rejects-with-message` MUST
- `reply-clears-timer-and-pending-entry` MUST
- `unmatched-reply-ignored` MUST
- `worker-error-rejects-all-pending` MUST
- `worker-exit-rejects-all-pending` MUST
- `crash-or-exit-clears-worker-reference-conditionally` MUST
- `failall-tolerates-empty-pending` MUST
- `terminated-worker-exit-cascades-to-sibling-pending` MUST
- `no-single-flight-guard` MUST

# Status Server Monitor Worker Client

## Overview

`MonitorWorkerClient` (`packages/web/packages/status-server/src/monitor/worker-client.ts`) is the main-thread handle to the monitor worker (`worker.ts`). The file's own header comment states the split directly: "the scheduler stays on the main thread (single-flight, watchdog, cadence, /health staleness) and each cycle becomes one RPC to the worker; console output from the cycle still reaches the container logs because workers share the process's stdio." `MonitorWorkerClient` owns exactly one thing: the lifecycle of the `Worker` instance that runs `runMonitorCycle` (the `cycle-runner.ts` composition, invoked by `worker.ts`) off the main thread, plus the request/reply correlation for one RPC (`runCycle`) per call.

It is deliberately self-healing. The header comment: "a cycle that exceeds `cycleTimeoutMs` gets its worker TERMINATED and the next cycle spawns a fresh one — a wedged provider chain recovers in-process instead of via the supervisor's container restart (which stays as the backstop of last resort). An unexpected worker crash likewise fails the in-flight cycle and respawns lazily." The class is generic over the connection type (`Conn`) specifically so this module never has to import a concrete connection type — the class comment on `MonitorWorkerData` states this is "so this file never has to name `LibsqlConnection` (it lives under `../libsql/`, which this file — unlike `worker.ts` — may not import)."

## Behavioral Requirements

### Construction and Generic Connection Type

- **generic-connection-parameter**: `MonitorWorkerClient<Conn = unknown>` MUST accept its database connection value only as an opaque generic type parameter and MUST NOT import or reference any concrete connection type of its own.
- **constructor-injected-configuration**: The constructor MUST accept exactly one `opts` argument shaped `{ cycleTimeoutMs: number; workerData: { db: Conn; config: StatusConfig } }` and MUST store it unchanged for the lifetime of the instance; every later `spawn()` call MUST read `db` and `config` from that same stored value.

### Spawn and Worker Entry Resolution

- **lazy-spawn-on-first-call**: `runCycle` MUST spawn a `Worker` only when no worker currently exists (`this.worker ??= this.spawn()`) and MUST reuse the existing worker on every subsequent call until it is cleared to `null` by a timeout, a crash, or an exit.
- **worker-entry-via-package-exports**: `spawn()` MUST resolve the worker module's path through the `status-server` package's own `exports` map — `createRequire(import.meta.url).resolve("@agentic-toolkit/status-server/worker")` — and MUST NOT use a relative filesystem path to `worker.ts`.
- **cooldowns-attached-at-spawn**: `spawn()` MUST construct the `Worker`'s `workerData` as the stored `opts.workerData` (`db`, `config`) plus a `cooldowns` field set to the current return value of `cooldownState()`, and this `cooldowns` field MUST NOT be read from the caller-supplied `opts.workerData`.
- **cooldown-buffer-shared-across-respawns**: Every respawn (a new `spawn()` call after the worker reference was cleared) MUST attach the same live `cooldownState()` buffer as the previous spawn, so a provider cooldown recorded before a respawn remains in force afterward.

### Cycle Request Dispatch

- **monotonic-sequence-numbers**: Each `runCycle` call MUST assign the request a `seq` value of `++this.seq`, strictly greater than every `seq` value assigned by any earlier call on the same instance, starting at `1` for the instance's first call, and this counter MUST NOT be reset by a respawn.
- **single-request-per-call**: `runCycle` MUST post exactly one `CycleRequest` message (`{ seq, fullSync }`) to the worker per call, and MUST NOT post more than one message for that call under any circumstance.

### Timeout Handling

- **cycle-timeout-rejection-message**: If no `CycleReply` for a call's `seq` arrives within `opts.cycleTimeoutMs` milliseconds, the call's promise MUST reject with an `Error` whose message is exactly `` monitor cycle exceeded <cycleTimeoutMs>ms — worker terminated; next cycle respawns it `` , with `<cycleTimeoutMs>` substituted by the configured value.
- **timeout-terminates-and-clears-worker**: On that same timeout, the client MUST remove the timed-out `seq` from `pending`, MUST clear its stored worker reference to `null`, and MUST call `worker.terminate()` on the timed-out worker, so the next `runCycle` call spawns a fresh worker.

### Reply Correlation

- **reply-ok-resolves-void**: A `CycleReply` with `ok: true` MUST resolve the pending promise matching its `seq` with no value.
- **reply-not-ok-rejects-with-message**: A `CycleReply` with `ok: false` MUST reject the pending promise matching its `seq` with an `Error` whose message is the reply's `error` field when present, or the literal string `monitor cycle failed` when `error` is absent.
- **reply-clears-timer-and-pending-entry**: On receiving any `CycleReply` that matches a `seq` still in `pending`, the client MUST clear that entry's timeout timer and remove the entry from `pending` before resolving or rejecting its promise.
- **unmatched-reply-ignored**: A `CycleReply` whose `seq` has no entry in `pending` (already timed out and removed, or never issued) MUST be ignored — the client MUST NOT throw, log, or otherwise act on it.

### Worker Crash and Exit

- **worker-error-rejects-all-pending**: On the worker's `"error"` event, the client MUST reject every entry currently in `pending` with an `Error` whose message is `` monitor worker crashed: <err.message> `` .
- **worker-exit-rejects-all-pending**: On the worker's `"exit"` event, regardless of exit code, the client MUST reject every entry currently in `pending` with an `Error` whose message is `` monitor worker exited (<code>) `` .
- **crash-or-exit-clears-worker-reference-conditionally**: On either event, the client MUST clear its stored worker reference to `null` only if that reference still points at the worker instance the event fired on (`this.worker === worker`), leaving it untouched if a newer worker has already replaced it.
- **failall-tolerates-empty-pending**: The crash/exit handling MUST NOT throw when `pending` is already empty — including the case where `"error"` and `"exit"` both fire for the same crash, or where an "exit" follows a `terminate()` whose own timeout branch already removed and settled that entry.
- **terminated-worker-exit-cascades-to-sibling-pending**: When a `terminate()` call (from a timeout on one `seq`) causes the worker's `"exit"` event to fire, that event MUST still reject every OTHER entry currently in `pending` for that worker — even one whose own `cycleTimeoutMs` window has not yet elapsed — with the exit-event message, not a timeout message.

### Concurrency

- **no-single-flight-guard**: `MonitorWorkerClient` MUST NOT prevent two or more `runCycle` calls from being in flight simultaneously against the same worker; each MUST be tracked independently by its own `seq` in `pending`, with no serialization of the underlying `postMessage` calls.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.cycleTimeoutMs` (constructor parameter) | `number` | none — caller-supplied, required | Milliseconds one `runCycle` call waits for a `CycleReply` before the pending promise rejects and the worker is terminated (cycle-timeout-rejection-message, timeout-terminates-and-clears-worker). Not validated or clamped by this file — see Edge Cases › Boundary values. |
| `opts.workerData.db` (constructor parameter) | `Conn` (generic) | none — caller-supplied, required | Opaque connection value forwarded unchanged into every spawned worker's `workerData.db`. This file never inspects or opens it; `worker.ts` is what validates and opens it. |
| `opts.workerData.config` (constructor parameter) | `StatusConfig` | none — caller-supplied, required | Forwarded unchanged into every spawned worker's `workerData.config`. See Privacy for the credential/secret fields it carries. |
| `cooldowns` (spawn-added `workerData` field) | `SharedArrayBuffer` | current return value of `cooldownState()` (module-level singleton in `@agentic-toolkit/deploy-platform/cooldown`) | Added by `spawn()` itself on every call; never read from `opts.workerData` — see cooldowns-attached-at-spawn. |
| Worker entry module | fixed string constant | `"@agentic-toolkit/status-server/worker"`, resolved via `createRequire(import.meta.url).resolve(...)` | Not configurable by the caller; hardcoded inside `spawn()` — see worker-entry-via-package-exports. |

## Localization

This file has no user-visible UI, but it does build four hardcoded English `Error` messages that propagate to its caller (and from there, potentially, to an operator-facing log or alert). It routes through no localization mechanism.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `monitor cycle exceeded <cycleTimeoutMs>ms — worker terminated; next cycle respawns it` | Rejection when a `runCycle` call's timeout elapses with no reply (cycle-timeout-rejection-message) |
| n/a | `<error>` (the `CycleReply.error` value, verbatim) | Rejection when a reply arrives with `ok: false` and an `error` string (reply-not-ok-rejects-with-message) |
| n/a | `monitor cycle failed` | Rejection when a reply arrives with `ok: false` and no `error` string (reply-not-ok-rejects-with-message) |
| n/a | `monitor worker crashed: <err.message>` | Rejection of every pending call on the worker's `"error"` event (worker-error-rejects-all-pending) |
| n/a | `monitor worker exited (<code>)` | Rejection of every pending call on the worker's `"exit"` event (worker-exit-rejects-all-pending) |

