---
id: bd58dfa4-13f8-4e92-adbe-45f8a020168d
title: Monitor Worker Client
domain: agentictoolkit://cookbook/status/service/monitor/worker-client
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Self-healing background-worker RPC client that spawns the monitor cycle's worker, times out a wedged one, and respawns it sharing the provider-cooldown buffer.
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
- agentictoolkit://cookbook/status/service/config
- agentictoolkit://cookbook/status/service/monitor/cycle-runner
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

# Monitor Worker Client

## Overview

The worker client is the scheduler's handle to the monitor's background
worker. It keeps the scheduler itself (single-flight guarding, watchdog,
cadence, staleness reporting) off the worker's own thread of execution, and
turns each monitor cycle into one request/reply round trip to that worker.
Output the cycle produces still reaches the same process's logs, because the
worker shares its host's standard output.

It is deliberately self-healing: a cycle that exceeds its configured timeout
has its worker terminated, and the next cycle spawns a fresh one — a wedged
provider chain recovers in-process rather than through the surrounding
supervisor's own restart, which remains the backstop of last resort. An
unexpected worker crash likewise fails the in-flight cycle and lazily
respawns on the next call. The client accepts its database connection value
only as an opaque type it never inspects, specifically so it never has to
name a concrete connection type of its own.

## Behavioral Requirements

### Construction and Opaque Connection Type

- **generic-connection-parameter**: The worker client MUST accept its database connection value only as an opaque type parameter and MUST NOT import or reference any concrete connection type of its own.
- **constructor-injected-configuration**: The constructor MUST accept exactly one configuration argument shaped as a cycle-timeout duration plus worker data carrying the connection value and the status configuration, and MUST store it unchanged for the lifetime of the instance; every later spawn MUST read the connection value and configuration from that same stored value.

### Spawn and Worker Entry Resolution

- **lazy-spawn-on-first-call**: Running a cycle MUST spawn a worker only when no worker currently exists, and MUST reuse the existing worker on every subsequent call until it is cleared to nothing by a timeout, a crash, or an exit.
- **worker-entry-via-package-exports**: Spawning MUST resolve the worker's entry point through the host package's own published-exports mechanism, and MUST NOT use a relative filesystem path to the worker's source file.
- **cooldowns-attached-at-spawn**: Spawning MUST construct the worker's data as the stored connection value and status configuration plus a cooldowns field set to the current value of the shared cooldown-state buffer, and this cooldowns field MUST NOT be read from the caller-supplied worker data.
- **cooldown-buffer-shared-across-respawns**: Every respawn (a new spawn after the worker reference was cleared) MUST attach the same live cooldown-state buffer as the previous spawn, so a provider cooldown recorded before a respawn remains in force afterward.

### Cycle Request Dispatch

- **monotonic-sequence-numbers**: Each cycle run MUST assign the request a sequence number strictly greater than every sequence number assigned by any earlier call on the same instance, starting at `1` for the instance's first call, and this counter MUST NOT be reset by a respawn.
- **single-request-per-call**: Running a cycle MUST post exactly one cycle-request message (carrying the sequence number and a full-sync flag) to the worker per call, and MUST NOT post more than one message for that call under any circumstance.

### Timeout Handling

- **cycle-timeout-rejection-message**: If no cycle-reply for a call's sequence number arrives within the configured cycle-timeout duration, the call's promise MUST reject with an error whose message is exactly `` monitor cycle exceeded <cycleTimeoutMs>ms — worker terminated; next cycle respawns it `` , with `<cycleTimeoutMs>` substituted by the configured value in milliseconds.
- **timeout-terminates-and-clears-worker**: On that same timeout, the client MUST remove the timed-out sequence number's entry from the pending-request table, MUST clear its stored worker reference to nothing, and MUST terminate the timed-out worker, so the next cycle run spawns a fresh worker.

### Reply Correlation

- **reply-ok-resolves-void**: A cycle-reply carrying an ok flag of `true` MUST resolve the pending promise matching its sequence number with no value.
- **reply-not-ok-rejects-with-message**: A cycle-reply carrying an ok flag of `false` MUST reject the pending promise matching its sequence number with an error whose message is the reply's error field when present, or the literal string `monitor cycle failed` when the error field is absent.
- **reply-clears-timer-and-pending-entry**: On receiving any cycle-reply that matches a sequence number still in the pending-request table, the client MUST clear that entry's timeout timer and remove the entry from the table before resolving or rejecting its promise.
- **unmatched-reply-ignored**: A cycle-reply whose sequence number has no entry in the pending-request table (already timed out and removed, or never issued) MUST be ignored — the client MUST NOT throw, log, or otherwise act on it.

### Worker Crash and Exit

- **worker-error-rejects-all-pending**: On the worker's error event, the client MUST reject every entry currently in the pending-request table with an error whose message is `` monitor worker crashed: <err.message> `` .
- **worker-exit-rejects-all-pending**: On the worker's exit event, regardless of exit code, the client MUST reject every entry currently in the pending-request table with an error whose message is `` monitor worker exited (<code>) `` .
- **crash-or-exit-clears-worker-reference-conditionally**: On either event, the client MUST clear its stored worker reference to nothing only if that reference still points at the worker instance the event fired on, leaving it untouched if a newer worker has already replaced it.
- **failall-tolerates-empty-pending**: The crash/exit handling MUST NOT throw when the pending-request table is already empty — including the case where an error event and an exit event both fire for the same crash, or where an exit event follows a termination whose own timeout branch already removed and settled that entry.
- **terminated-worker-exit-cascades-to-sibling-pending**: When a termination call (from a timeout on one sequence number) causes the worker's exit event to fire, that event MUST still reject every OTHER entry currently in the pending-request table for that worker — even one whose own cycle-timeout window has not yet elapsed — with the exit-event message, not a timeout message.

### Concurrency

- **no-single-flight-guard**: The worker client MUST NOT prevent two or more cycle runs from being in flight simultaneously against the same worker; each MUST be tracked independently by its own sequence number in the pending-request table, with no serialization of the underlying message posts.

## Appearance

Not applicable — this is a background-worker RPC client, not a visual component.

## States

Not applicable — this is a background-worker RPC client, not a visual component; its runtime states (no worker spawned, a worker with in-flight cycles, a worker mid-termination) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a background-worker RPC client, not a visual component.

## Conformance Test Vectors

No test exercises the worker client directly (see Compliance); every vector below is traced to the component's own specified behavior, except where an integration test is cited.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-worker-client-001 | lazy-spawn-on-first-call, constructor-injected-configuration | A newly constructed worker client with a configured cycle-timeout duration; one cycle run called once | Spawning is invoked exactly once and the resulting worker is stored as the client's current worker |
| status-server-monitor-worker-client-002 | monotonic-sequence-numbers, single-request-per-call | Two sequential cycle runs against the same client, the worker stubbed to reply immediately each time | The worker receives exactly two request messages, carrying sequence numbers `1` then `2`, each value used exactly once |
| status-server-monitor-worker-client-003 | cycle-timeout-rejection-message, timeout-terminates-and-clears-worker | A worker client configured with a 50-millisecond cycle timeout; one cycle run called; the worker never replies | The promise rejects with the message "monitor cycle exceeded 50ms — worker terminated; next cycle respawns it"; the worker is terminated; a following cycle run spawns a new worker, since the worker reference was cleared |
| status-server-monitor-worker-client-004 | reply-ok-resolves-void | The worker posts a reply for sequence `1` with an ok flag of `true` | The promise resolves with no value |
| status-server-monitor-worker-client-005 | reply-not-ok-rejects-with-message | The worker posts a reply for sequence `1` with an ok flag of `false` and an error field of "boom" | The promise rejects with the message "boom" |
| status-server-monitor-worker-client-006 | reply-not-ok-rejects-with-message | The worker posts a reply for sequence `1` with an ok flag of `false` and no error field | The promise rejects with the message "monitor cycle failed" |
| status-server-monitor-worker-client-007 | unmatched-reply-ignored | The worker posts a reply for sequence `999`, a sequence number never issued (or already timed out and removed) | No promise settles, no exception is thrown, and the pending-request table is unaffected |
| status-server-monitor-worker-client-008 | worker-error-rejects-all-pending, crash-or-exit-clears-worker-reference-conditionally, no-single-flight-guard | Two cycle runs in flight (sequence `1` and `2`) against the same worker; the worker's error event fires with the message "kaboom" | Both promises reject with the message "monitor worker crashed: kaboom"; the client's worker reference is cleared, so the next cycle run respawns |
| status-server-monitor-worker-client-009 | worker-exit-rejects-all-pending, terminated-worker-exit-cascades-to-sibling-pending | Two cycle runs in flight (sequence `1` and `2`); sequence `1`'s cycle timeout elapses first (terminating the worker), then the worker's exit event fires with code `1` before sequence `2` has replied or itself timed out | Sequence `1` is already rejected with the timeout message; sequence `2` — which had not itself timed out — rejects with the message "monitor worker exited (1)" |
| status-server-monitor-worker-client-010 | failall-tolerates-empty-pending | The worker's error event fires, then its exit event fires immediately afterward, with no new cycle run started between the two | The second crash-handling pass runs against an empty pending-request table and throws nothing |
| status-server-monitor-worker-client-011 | worker-entry-via-package-exports | The worker entry's resolution mechanism exercised in an environment with no development-time source loader available | The resolved entry is the package's built distribution of the worker module, reached through the host package's own published-exports mechanism, and a spawned worker completes one cycle round trip — integration evidence exercises the same resolution mechanism and the worker's own entry point directly, not through the worker client itself (see Compliance) |
| status-server-monitor-worker-client-012 | cooldowns-attached-at-spawn, cooldown-buffer-shared-across-respawns | Two respawns of the worker (for example after two separate crashes), with the shared cooldown-state buffer stubbed to return the same fixed buffer instance on both calls | Both resulting worker constructions receive a cooldowns field that is the identical buffer instance |
| status-server-monitor-worker-client-013 | generic-connection-parameter | Static read of the worker client's declaration and import list | The client accepts its connection value only as an opaque type parameter; the client imports no concrete connection type of its own |
| status-server-monitor-worker-client-014 | reply-clears-timer-and-pending-entry | The worker posts a reply for sequence `1` with an ok flag of `true` well within the cycle-timeout duration; the test then waits past the original timeout duration with no further action | No timeout-triggered rejection ever fires for sequence `1` (its timer was cleared and its entry removed on the reply) |

## Edge Cases

- **Null and empty input**: a not-ok cycle-reply with no error field MUST fall back to the literal message `monitor cycle failed` (reply-not-ok-rejects-with-message) — MUST. A connection value or status configuration of null or undefined is passed through unchanged into the spawned worker; validating it is entirely the worker's own job, not the client's — MUST.
- **Boundary values**: a configured cycle-timeout duration of `0`, a negative number, or an invalid number is not validated or clamped anywhere in this component; it is handed directly to the underlying timer mechanism, whose own runtime semantics govern the resulting delay — MUST NOT be read as this component enforcing any minimum or maximum. The sequence counter increments once per cycle run for the lifetime of the client instance, never reset by a respawn, with no wraparound guard against the platform's largest safely representable integer — undocumented if ever reached, though unreachable at any real monitor cadence.
- **Concurrent access**: nothing in this component serializes cycle runs — two or more overlapping calls against the same worker are each dispatched immediately and tracked independently by their own sequence number (no-single-flight-guard) — MUST. A direct consequence: when one call's timeout terminates the shared worker, every OTHER call still pending against that same worker is rejected too, via the resulting exit event, not just the call that actually timed out (terminated-worker-exit-cascades-to-sibling-pending) — MUST.
- **Error states**: a cycle-reply carrying an ok flag of `false` rejects only its own matching entry (reply-not-ok-rejects-with-message) — MUST. An error or exit event on the worker rejects EVERY currently pending entry, whether or not each one individually timed out (worker-error-rejects-all-pending, worker-exit-rejects-all-pending) — MUST. A reply for a sequence number no longer present in the pending-request table is silently ignored, with no throw and no log (unmatched-reply-ignored) — MUST.
- **Offline / disconnected state**: this component has no network dependency of its own — it exchanges only in-process messages, never an HTTP request. Its equivalent of "connectivity loss" is losing the underlying worker (a crash, a forced termination on timeout, or an unexpected exit), which is fully specified under Error states above; there is no additional degraded mode beyond what those requirements already define.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| cycle timeout (constructor parameter) | a duration in milliseconds | none — caller-supplied, required | How long one cycle run waits for a cycle-reply before the pending promise rejects and the worker is terminated (cycle-timeout-rejection-message, timeout-terminates-and-clears-worker). Not validated or clamped by this component — see Edge Cases › Boundary values. |
| connection value (constructor parameter, part of worker data) | an opaque connection type | none — caller-supplied, required | Forwarded unchanged into every spawned worker's data. This component never inspects or opens it; the worker itself is what validates and opens it. |
| status configuration (constructor parameter, part of worker data) | a status configuration record | none — caller-supplied, required | Forwarded unchanged into every spawned worker's data. See Privacy for the credential/secret fields it carries. |
| cooldowns (spawn-added worker-data field) | a shared cooldown-state buffer | current value of the shared cooldown-state buffer (a process-wide singleton) | Added by the spawn step itself on every call; never read from the caller-supplied worker data — see cooldowns-attached-at-spawn. |
| Worker entry module | fixed identifier | resolved via the host package's own published-exports mechanism | Not configurable by the caller; hardcoded inside the spawn step — see worker-entry-via-package-exports. |

## Deep Linking

Not applicable: this component defines no application URL scheme or HTTP route of its own — its only "address" is a package export identifier resolved at spawn time, not a deep-link target.

## Localization

This component has no user-visible UI, but it does build four hardcoded English error messages that propagate to its caller (and from there, potentially, to an operator-facing log or alert). It routes through no localization mechanism.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `monitor cycle exceeded <cycleTimeoutMs>ms — worker terminated; next cycle respawns it` | Rejection when a cycle run's timeout elapses with no reply (cycle-timeout-rejection-message) |
| n/a | `<error>` (the reply's error value, verbatim) | Rejection when a reply arrives with an ok flag of `false` and an error string (reply-not-ok-rejects-with-message) |
| n/a | `monitor cycle failed` | Rejection when a reply arrives with an ok flag of `false` and no error string (reply-not-ok-rejects-with-message) |
| n/a | `monitor worker crashed: <err.message>` | Rejection of every pending call on the worker's error event (worker-error-rejects-all-pending) |
| n/a | `monitor worker exited (<code>)` | Rejection of every pending call on the worker's exit event (worker-exit-rejects-all-pending) |

## Accessibility Options

Not applicable: this component has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this component consults no feature-flag system. Its only behavioral lever is the constructor's configured cycle-timeout duration, a caller-supplied value, not a flag lookup this component performs.

## Analytics

Not applicable: this component emits no analytics or usage-telemetry event describing its own execution.

## Privacy

- **Data collected**: this component itself collects nothing; it holds the exact worker data it was constructed with — a connection value (an opaque connection type) and a full status configuration, including credentials and secrets (the provider API tokens and other secrets) — and forwards that value unchanged into every worker it spawns.
- **Storage**: the constructor's configuration (including the connection value and status configuration) is held in memory for the lifetime of the worker client instance, re-read on every respawn; this component never writes it to disk.
- **Transmission**: the only "transmission" this component performs is handing its worker data (plus the cooldowns buffer it adds) to the newly constructed worker, crossing an in-process structured-clone boundary — never a network call. No credential or secret value is ever written into any of this component's own error messages (see Localization); those name only a timeout duration, an exit code, or a reply's own error/message text.
- **Retention**: not applicable beyond the "Storage" note above — this component keeps no separate history of past connection/configuration values; it only ever holds the one it was constructed with.

## Logging

This component makes no logging call of its own — no console output and no structured logger. Every failure it produces surfaces exclusively as a rejected promise to its caller (see Behavioral Requirements and Localization); it is the caller's responsibility to log or alert on that rejection.

| Event | Level | Message |
|-------|-------|---------|
| n/a | n/a | This component emits no log output at any level. |

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this pattern models `MonitorWorkerClient` as an `actor` (so `pending`/`seq`/the worker handle are protected from concurrent mutation without a manual lock), spawning the cycle's work as a `Task` rather than an OS-level worker thread; a "kill a wedged task" guarantee equivalent to `Worker.terminate()` requires cooperative cancellation (`Task.isCancelled` checks inside the cycle) since Swift `Task` cancellation cannot forcibly stop code that never checks it.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the client as a class holding a `Channel`-backed request/reply pair per in-flight call (the `pending` map analog is a `ConcurrentHashMap<Long, CompletableDeferred<Unit>>`), launches the cycle work in its own coroutine, and enforces `cycleTimeoutMs` with `withTimeout`/`withTimeoutOrNull` — which, like `Task` cancellation, is cooperative: a coroutine that never suspends at a cancellation point cannot be forcibly killed the way `Worker.terminate()` kills an OS thread.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/worker-client.ts` as a plain exported class on the Node status backend, imported by `worker.ts`'s sibling wiring and re-exported from `index.ts`. It depends only on `node:worker_threads`, `node:module`'s `createRequire`, and the shared `cooldownState()`/`attachCooldownState()` pair from `@agentic-toolkit/deploy-platform/cooldown` — no framework of its own.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern would typically reach for a background `Task` rather than a separate OS thread/process the way Node's `Worker` isolates it here; the "why isolate the cycle" rationale in this file's own header comment (keeping the scheduler's watchdog and cadence logic responsive) has no direct AppKit/UIKit analogue unless the host app also multiplexes a UI event loop with this work.
- **WinUI 3**: a .NET port models the request/reply correlation with a `ConcurrentDictionary<long, TaskCompletionSource>` in place of `pending`, an `Interlocked.Increment(ref _seq)` in place of `++this.seq` (a stricter analog than the source needs, since the source's single JS main thread makes `++this.seq` inherently safe, while a WinUI host's UI thread and background `Task`s are not single-threaded), and `CancellationTokenSource.CancelAfter(cycleTimeoutMs)` in place of the `setTimeout`. The critical divergence to flag: .NET `Task` cancellation is COOPERATIVE — a hung `Task` that never observes its `CancellationToken` cannot be forcibly killed the way `Worker.terminate()` kills an OS-level thread. Reproducing the source's "TERMINATE the wedged worker" guarantee exactly requires isolating the cycle in a separate OS process (`Process.Start`, killed with `Process.Kill()` on timeout) rather than a `Task`; a `Task`-based port that skips this can only abandon a wedged cycle, not truly stop it, and that gap SHOULD be called out to whoever approves the port. `System.Threading.Channels.Channel<T>` is the .NET analog of the `postMessage`/`on("message")` request/reply pipe. `ObservableCollection`/`INotifyPropertyChanged` do not apply here: this client has no UI-bound state of its own to expose.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/worker-client.ts` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/service/monitor/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
