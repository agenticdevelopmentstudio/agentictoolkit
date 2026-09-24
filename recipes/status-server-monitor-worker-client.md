---
id: bd58dfa4-13f8-4e92-adbe-45f8a020168d
title: Status Server Monitor Worker Client
domain: agentictoolkit://recipes/status-server-monitor-worker-client
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Self-healing worker_threads RPC client that spawns the monitor cycle worker,
  times out a wedged one, and respawns it sharing the provider-cooldown buffer.
platforms:
- typescript
- web
tags:
- monitor
- worker
- concurrency
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/concurrency/concurrency
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/code-quality/dependency-injection
related:
- agentictoolkit://recipes/status-server-config
- agentictoolkit://recipes/status-server-monitor-cycle-runner
references:
- packages/web/packages/status-server/src/monitor/worker-client.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/worker.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/cycle-runner.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/cooldown/provider-cooldown.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/cooldown/index.ts (agentictoolkit)
- packages/web/packages/status-server/package.json (agentictoolkit)
- packages/web/packages/status-server/test/worker-boot.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/helpers/worker-boot-driver.mjs (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a worker_threads RPC client, not a visual component.

## States

Not applicable — this is a worker_threads RPC client, not a visual component; its runtime states (no worker spawned, a worker with in-flight cycles, a worker mid-termination) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a worker_threads RPC client, not a visual component.

## Conformance Test Vectors

No test file imports or instantiates `MonitorWorkerClient` directly (see Compliance); every vector below is traced to reading `worker-client.ts` itself, except where a test is cited.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-worker-client-001 | lazy-spawn-on-first-call, constructor-injected-configuration | `new MonitorWorkerClient({ cycleTimeoutMs: 5000, workerData })`; call `runCycle(false)` once | `spawn()` is invoked exactly once and its returned `Worker` is stored as `this.worker` — traced to `runCycle`'s `this.worker ??= this.spawn()` guard |
| status-server-monitor-worker-client-002 | monotonic-sequence-numbers, single-request-per-call | Two sequential `runCycle(false)` calls against the same client, worker stubbed to reply immediately each time | The worker receives exactly two `postMessage` calls, carrying `seq` `1` then `2`, each value used exactly once |
| status-server-monitor-worker-client-003 | cycle-timeout-rejection-message, timeout-terminates-and-clears-worker | `new MonitorWorkerClient({ cycleTimeoutMs: 50, workerData })`; call `runCycle(false)`; the worker never replies | The promise rejects with `Error("monitor cycle exceeded 50ms — worker terminated; next cycle respawns it")`; `worker.terminate()` is called; a following `runCycle` call invokes `spawn()` again (worker reference was cleared) |
| status-server-monitor-worker-client-004 | reply-ok-resolves-void | Worker posts `{ seq: 1, ok: true }` for the in-flight call | The promise resolves to `undefined` |
| status-server-monitor-worker-client-005 | reply-not-ok-rejects-with-message | Worker posts `{ seq: 1, ok: false, error: "boom" }` | The promise rejects with `Error("boom")` |
| status-server-monitor-worker-client-006 | reply-not-ok-rejects-with-message | Worker posts `{ seq: 1, ok: false }` with no `error` field | The promise rejects with `Error("monitor cycle failed")` |
| status-server-monitor-worker-client-007 | unmatched-reply-ignored | Worker posts `{ seq: 999, ok: true }` for a `seq` that was never issued (or already timed out and removed) | No promise settles, no exception is thrown, and `pending` is unaffected |
| status-server-monitor-worker-client-008 | worker-error-rejects-all-pending, crash-or-exit-clears-worker-reference-conditionally, no-single-flight-guard | Two `runCycle` calls in flight (`seq` `1` and `2`) against the same worker; the worker's `"error"` event fires with `new Error("kaboom")` | Both promises reject with `Error("monitor worker crashed: kaboom")`; the client's worker reference is cleared to `null`, so the next `runCycle` call respawns |
| status-server-monitor-worker-client-009 | worker-exit-rejects-all-pending, terminated-worker-exit-cascades-to-sibling-pending | Two `runCycle` calls in flight (`seq` `1` and `2`); `seq` `1`'s `cycleTimeoutMs` elapses first (terminating the worker), then the worker's `"exit"` event fires with code `1` before `seq` `2` has replied or itself timed out | `seq` `1` is already rejected with the timeout message; `seq` `2` — which had not itself timed out — rejects with `Error("monitor worker exited (1)")` |
| status-server-monitor-worker-client-010 | failall-tolerates-empty-pending | The worker's `"error"` event fires, then its `"exit"` event fires immediately afterward, with no new `runCycle` call started between the two | The second crash-handling pass runs against an empty `pending` map and throws nothing |
| status-server-monitor-worker-client-011 | worker-entry-via-package-exports | `spawn()`'s resolution mechanism exercised under bare `node` (no `tsx`/TypeScript loader in `execArgv`) | The resolved entry is the package's built `dist/monitor/worker.js`, reached through `@agentic-toolkit/status-server/worker`'s `exports` map, and a spawned worker completes one cycle round trip — `worker-boot.int.test.ts` › "completes a cycle round-trip via the package-resolved worker entry" (this test exercises the same resolution mechanism and `worker.ts` directly via a bare `Worker`, not through the `MonitorWorkerClient` class — see Compliance) |
| status-server-monitor-worker-client-012 | cooldowns-attached-at-spawn, cooldown-buffer-shared-across-respawns | Two respawns of the worker (e.g. after two separate crashes), with `cooldownState()` stubbed to return the same fixed `SharedArrayBuffer` instance on both calls | Both resulting `new Worker(...)` calls receive a `workerData.cooldowns` field that is the identical (`===`) `SharedArrayBuffer` instance — traced to `spawn()`'s `{ ...this.opts.workerData, cooldowns: cooldownState() }` |
| status-server-monitor-worker-client-013 | generic-connection-parameter | Static read of `worker-client.ts`'s class declaration and import list | The class is declared `MonitorWorkerClient<Conn = unknown>`; the file imports no concrete connection type (no `LibsqlConnection`, no `openLibsql`, no `createLibsqlStorage`) |
| status-server-monitor-worker-client-014 | reply-clears-timer-and-pending-entry | Worker posts `{ seq: 1, ok: true }` well within `cycleTimeoutMs`; the test then waits past the original `cycleTimeoutMs` duration with no further action | No timeout-triggered rejection ever fires for `seq` `1` (its timer was cleared and its entry removed on the reply) |

## Edge Cases

- **Null and empty input**: a not-`ok` `CycleReply` with no `error` field MUST fall back to the literal message `monitor cycle failed` (reply-not-ok-rejects-with-message) — MUST. A `workerData.db`/`workerData.config` of `null` or `undefined` is passed through unchanged into the spawned worker; validating it is entirely `worker.ts`'s job (its own `if (!conn?.url) throw ...` / `if (!config) throw ...`), not this file's — MUST.
- **Boundary values**: `opts.cycleTimeoutMs` of `0`, a negative number, or `NaN` is not validated or clamped anywhere in this file; it is handed directly to `setTimeout`, whose own runtime semantics govern the resulting delay — MUST NOT be read as this file enforcing any minimum or maximum. `seq` increments once per `runCycle` call for the lifetime of the client instance, never reset by a respawn, with no wraparound guard against `Number.MAX_SAFE_INTEGER` — undocumented if ever reached, though unreachable at any real monitor cadence.
- **Concurrent access**: nothing in this file serializes `runCycle` calls — two or more overlapping calls against the same worker are each dispatched immediately and tracked independently by their own `seq` (no-single-flight-guard) — MUST. A direct consequence: when one call's timeout terminates the shared worker, every OTHER call still pending against that same worker is rejected too, via the resulting `"exit"` event, not just the call that actually timed out (terminated-worker-exit-cascades-to-sibling-pending) — MUST.
- **Error states**: a `CycleReply` with `ok: false` rejects only its own matching entry (reply-not-ok-rejects-with-message) — MUST. A `"error"` or `"exit"` event on the worker rejects EVERY currently pending entry, whether or not each one individually timed out (worker-error-rejects-all-pending, worker-exit-rejects-all-pending) — MUST. A reply for a `seq` no longer present in `pending` is silently ignored, with no throw and no log (unmatched-reply-ignored) — MUST.
- **Offline / disconnected state**: this component has no network dependency of its own — it exchanges only in-process `worker_threads` messages, never an HTTP request. Its equivalent of "connectivity loss" is losing the underlying worker thread (a crash, a forced termination on timeout, or an unexpected exit), which is fully specified under Error states above; there is no additional degraded mode beyond what those requirements already define.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.cycleTimeoutMs` (constructor parameter) | `number` | none — caller-supplied, required | Milliseconds one `runCycle` call waits for a `CycleReply` before the pending promise rejects and the worker is terminated (cycle-timeout-rejection-message, timeout-terminates-and-clears-worker). Not validated or clamped by this file — see Edge Cases › Boundary values. |
| `opts.workerData.db` (constructor parameter) | `Conn` (generic) | none — caller-supplied, required | Opaque connection value forwarded unchanged into every spawned worker's `workerData.db`. This file never inspects or opens it; `worker.ts` is what validates and opens it. |
| `opts.workerData.config` (constructor parameter) | `StatusConfig` | none — caller-supplied, required | Forwarded unchanged into every spawned worker's `workerData.config`. See Privacy for the credential/secret fields it carries. |
| `cooldowns` (spawn-added `workerData` field) | `SharedArrayBuffer` | current return value of `cooldownState()` (module-level singleton in `@agentic-toolkit/deploy-platform/cooldown`) | Added by `spawn()` itself on every call; never read from `opts.workerData` — see cooldowns-attached-at-spawn. |
| Worker entry module | fixed string constant | `"@agentic-toolkit/status-server/worker"`, resolved via `createRequire(import.meta.url).resolve(...)` | Not configurable by the caller; hardcoded inside `spawn()` — see worker-entry-via-package-exports. |

## Deep Linking

Not applicable: this file defines no application URL scheme or HTTP route of its own — its only "address" is an npm package export string (`@agentic-toolkit/status-server/worker`) resolved through `createRequire`, not a deep-link target.

## Localization

This file has no user-visible UI, but it does build four hardcoded English `Error` messages that propagate to its caller (and from there, potentially, to an operator-facing log or alert). It routes through no localization mechanism.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `monitor cycle exceeded <cycleTimeoutMs>ms — worker terminated; next cycle respawns it` | Rejection when a `runCycle` call's timeout elapses with no reply (cycle-timeout-rejection-message) |
| n/a | `<error>` (the `CycleReply.error` value, verbatim) | Rejection when a reply arrives with `ok: false` and an `error` string (reply-not-ok-rejects-with-message) |
| n/a | `monitor cycle failed` | Rejection when a reply arrives with `ok: false` and no `error` string (reply-not-ok-rejects-with-message) |
| n/a | `monitor worker crashed: <err.message>` | Rejection of every pending call on the worker's `"error"` event (worker-error-rejects-all-pending) |
| n/a | `monitor worker exited (<code>)` | Rejection of every pending call on the worker's `"exit"` event (worker-exit-rejects-all-pending) |

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system. Its only behavioral lever is the constructor's `opts.cycleTimeoutMs`, a caller-supplied value, not a flag lookup this file performs.

## Analytics

Not applicable: this file emits no analytics or usage-telemetry event describing its own execution.

## Privacy

- **Data collected**: this file itself collects nothing; it holds the exact `opts.workerData` value it was constructed with — `db` (an opaque connection value) and `config` (a full `StatusConfig`, including `config.credentials` and `config.secrets`, the provider API tokens and other secrets) — and forwards that value unchanged into every worker it spawns.
- **Storage**: the constructor's `opts` (including `workerData.db`/`workerData.config`) is held in memory for the lifetime of the `MonitorWorkerClient` instance, re-read on every respawn; this file never writes it to disk.
- **Transmission**: the only "transmission" this file performs is handing `workerData` (plus the `cooldowns` `SharedArrayBuffer` it adds) to `new Worker(...)`, which crosses the `worker_threads` structured-clone boundary within the same process — never a network call. No credential or secret value is ever written into any of this file's own `Error` messages (see Localization); those name only a timeout duration, an exit code, or a reply's own `error`/message text.
- **Retention**: not applicable beyond the "Storage" note above — this file keeps no separate history of past `config`/`db` values; it only ever holds the one it was constructed with.

## Logging

This file makes no logging call of its own — no `console.log`, no `console.error`, and no structured logger. Every failure it produces surfaces exclusively as a rejected `Promise` to its caller (see Behavioral Requirements and Localization); it is the caller's responsibility to log or alert on that rejection.

| Event | Level | Message |
|-------|-------|---------|
| n/a | n/a | This file emits no log output at any level. |

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this pattern models `MonitorWorkerClient` as an `actor` (so `pending`/`seq`/the worker handle are protected from concurrent mutation without a manual lock), spawning the cycle's work as a `Task` rather than an OS-level worker thread; a "kill a wedged task" guarantee equivalent to `Worker.terminate()` requires cooperative cancellation (`Task.isCancelled` checks inside the cycle) since Swift `Task` cancellation cannot forcibly stop code that never checks it.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the client as a class holding a `Channel`-backed request/reply pair per in-flight call (the `pending` map analog is a `ConcurrentHashMap<Long, CompletableDeferred<Unit>>`), launches the cycle work in its own coroutine, and enforces `cycleTimeoutMs` with `withTimeout`/`withTimeoutOrNull` — which, like `Task` cancellation, is cooperative: a coroutine that never suspends at a cancellation point cannot be forcibly killed the way `Worker.terminate()` kills an OS thread.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/worker-client.ts` as a plain exported class on the Node status backend, imported by `worker.ts`'s sibling wiring and re-exported from `index.ts`. It depends only on `node:worker_threads`, `node:module`'s `createRequire`, and the shared `cooldownState()`/`attachCooldownState()` pair from `@agentic-toolkit/deploy-platform/cooldown` — no framework of its own.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern would typically reach for a background `Task` rather than a separate OS thread/process the way Node's `Worker` isolates it here; the "why isolate the cycle" rationale in this file's own header comment (keeping the scheduler's watchdog and cadence logic responsive) has no direct AppKit/UIKit analogue unless the host app also multiplexes a UI event loop with this work.
- **WinUI 3**: a .NET port models the request/reply correlation with a `ConcurrentDictionary<long, TaskCompletionSource>` in place of `pending`, an `Interlocked.Increment(ref _seq)` in place of `++this.seq` (a stricter analog than the source needs, since the source's single JS main thread makes `++this.seq` inherently safe, while a WinUI host's UI thread and background `Task`s are not single-threaded), and `CancellationTokenSource.CancelAfter(cycleTimeoutMs)` in place of the `setTimeout`. The critical divergence to flag: .NET `Task` cancellation is COOPERATIVE — a hung `Task` that never observes its `CancellationToken` cannot be forcibly killed the way `Worker.terminate()` kills an OS-level thread. Reproducing the source's "TERMINATE the wedged worker" guarantee exactly requires isolating the cycle in a separate OS process (`Process.Start`, killed with `Process.Kill()` on timeout) rather than a `Task`; a `Task`-based port that skips this can only abandon a wedged cycle, not truly stop it, and that gap SHOULD be called out to whoever approves the port. `System.Threading.Channels.Channel<T>` is the .NET analog of the `postMessage`/`on("message")` request/reply pipe. `ObservableCollection`/`INotifyPropertyChanged` do not apply here: this client has no UI-bound state of its own to expose.

## Design Decisions

- **Decision**: resolve the worker entry through the package's own `exports` map (`@agentic-toolkit/status-server/worker`) rather than a relative path to `worker.ts`.
  **Rationale**: the source comment states it plainly — a container image ships no `tsx`/TypeScript loader, so a relative path to the `.ts` source "would work in dev and die on first boot in prod"; resolving through `exports` always lands on the built `dist/monitor/worker.js`, "the only form guaranteed runnable in that container." `worker-boot.int.test.ts` exercises exactly this resolution path under bare `node`.
  **Approved**: pending
- **Decision**: attach the shared `cooldownState()` buffer inside `spawn()` itself rather than accepting it as part of the caller-supplied `opts.workerData`.
  **Rationale**: the source comment states the monitor cycle (worker thread) and the API thread's dashboard enumerations poll the SAME provider tokens, so a 429 either sees must back both off; sourcing the buffer internally on every spawn — rather than trusting the caller to keep passing the current one — guarantees a respawned worker always re-adopts the live registry, so an in-force cooldown survives a respawn.
  **Approved**: pending
- **Decision**: on a cycle timeout, reject only that call's own pending entry directly and terminate the worker without awaiting `worker.terminate()`'s own returned promise, relying on the resulting `"exit"` event to clean up every other pending entry.
  **Rationale**: the source comment states the intent directly — "kill the whole thread so its abandoned work stops consuming the container, and let the next cycle start clean" — and separately notes "terminate() also fires 'exit', which is why failAll below must tolerate an already-settled entry." The practical effect, not spelled out in the timeout branch itself, is that a timeout on one in-flight cycle also fails every other cycle sharing that worker; a reader of only the timeout branch would not expect that.
  **Approved**: pending
- **Decision**: never reset `seq` across a respawn.
  **Rationale**: not called out in a comment, but it is what makes `unmatched-reply-ignored` correct — if `seq` were reset to a value a still-terminating old worker might still emit a stale reply for, that reply could be mismatched to an unrelated, newer cycle. A monotonically increasing `seq` for the instance's whole lifetime makes any stale reply from a terminated worker unambiguously unmatchable.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | partial | Reliability |

`unit-test-coverage` fails: no test file imports or constructs `MonitorWorkerClient`. `worker-boot.int.test.ts` exercises the same package-`exports` resolution mechanism and `worker.ts` directly through a bare `new Worker(...)` call in its driver script, which proves the worker entry boots under production conditions, but it never goes through the `MonitorWorkerClient` class itself — `runCycle`, the timeout/terminate/respawn path, `failAll`'s crash/exit handling, and the cooldown-buffer attachment on spawn are all unexercised by any existing test. `separation-of-concerns` passes: this file owns only worker lifecycle and RPC correlation, delegating all cycle logic to `cycle-runner.ts` via `worker.ts`, and never touches the connection type it is generic over. `explicit-error-handling` passes: every failure path (timeout, a not-`ok` reply, a worker crash, a worker exit) rejects its promise(s) explicitly with a descriptive message rather than swallowing anything; the one fire-and-forget call, `void worker.terminate()`, is intentional per the source's own framing of the container supervisor's restart as the backstop of last resort, not a silently dropped error. `error-recovery` and `graceful-degradation` pass: a wedged, crashed, or exited worker never crashes the client's host process — it fails only the in-flight cycle(s) and lazily respawns a fresh worker on the next call, exactly as the class's own header comment describes. `fault-tolerance` passes: an unmatched reply, an empty `pending` map on a second crash-handling pass, and a not-`ok` reply with no `error` field are all handled without throwing. `timeout-handling` passes: a timed-out cycle leaves the system in a defined, consistent state — the worker is terminated, the client's worker reference is cleared, and the next call spawns cleanly. `health-observability` is partial: a caller does get a specific, typed rejection reason for every failure mode (timeout, crash, exit, application-level failure), which is enough to build monitoring on top of, but this file itself emits no log line or metric of its own — unlike sibling files (`heartbeat.ts`, `cycle-runner.ts`) that `console.log`/`console.error` directly, a caller that does not thread the rejection into its own logging gets no visibility at all.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
