---
id: 8d827e9d-3638-4eaf-b04b-223b29b53389
title: Local Inference Guard
domain: agentictoolkit://cookbook/ai/models/local/local-inference-guard
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A guard for local-model inference: verdicts requests against RAM/pressure
  and serializes runs behind a FIFO mutex with a deadline.'
platforms:
- swift
- macos
tags:
- ai-plugin
- memory-guard
- local-inference
- concurrency
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/AIPluginKit/LocalInferenceGuard.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/ModelFitPolicy.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/LocalModelCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/SystemMemoryMonitor.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/DaemonProviderResolver.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/LocalInferenceGuardTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Local Inference Guard

## Overview

The guard is the memory guard the local-model chat pathway consults before
dispatching a chat request to a loopback ("local") model server. Given a
model name and base URL, its verdict operation asks the model catalog for
the model's on-disk size, asks the injected memory monitor for the machine's
physical RAM and latched memory-pressure level, and returns a verdict
(allow, block-with-reason, or defer-with-reason) from the model-fit policy.
Independently of that verdict, an exclusive-run operation serializes local
inference process-wide behind a single mutex, so two host features that each
trigger a local model load (e.g. summaries and oversight) cannot do so at
once; the mutex is a FIFO queue of parked acquirers with direct-handoff
release, and each exclusive run is bounded by a wall-clock deadline (600s by
default) after which the operation is cancelled and the guard reports a
deferred refusal. The guard's refusal error type (blocked/deferred) is a
distinct error type from the daemon's own completion error type: a guard
refusal is "terminal for this attempt" and must never be reinterpreted as a
transport failure eligible for the CLI fallback path.

## Behavioral Requirements

- **guard-refusal-cases**: The guard's refusal error type MUST provide
  exactly two cases, blocked and deferred, each carrying a human-readable
  reason string.
- **guard-refusal-description**: The refusal error's description MUST return
  the associated reason string unchanged for both the blocked and deferred
  cases.
- **guard-refusal-non-transport**: A guard refusal (blocked or deferred)
  MUST NOT be treated by a caller as a transport failure eligible for
  another provider path; a guard refusal is deliberately not the daemon's
  own completion error type, and it must never cascade into the CLI
  fallback path.
- **shared-default-instance**: The guard MUST provide one process-wide
  default instance, constructed from the production model catalog and
  memory monitor.
- **injectable-dependencies**: The guard's constructor MUST accept a
  substitutable model catalog and memory monitor, each defaulting to its
  production singleton, so a caller MAY construct a guard backed by fixed or
  fake behavior.
- **serialized-mutable-state**: The guard's mutable state (its busy flag and
  waiter queue) MUST be serialized so that no two operations can observe or
  mutate it concurrently — access is mutually exclusive rather than
  protected by ad hoc locking at each call site.
- **threshold-settings-override**: The verdict operation MUST read the warn
  and block percentage thresholds from the supplied settings reader under
  the model-fit policy's warn/block threshold keys and MUST use the parsed
  integer when one is present.
- **threshold-fallback-on-missing-or-invalid**: The verdict operation MUST
  fall back to the model-fit policy's default warn percentage (25) / default
  block percentage (50) when the settings reader returns no value for a
  threshold key, or returns a string that is not parseable as an integer.
- **disk-size-lookup-delegation**: The verdict operation MUST obtain the
  candidate model's on-disk size from the model catalog, and MUST treat "no
  size available" as "size unknown" rather than substituting a default
  size.
- **unknown-size-fail-open**: When the disk size is unknown (no tier), the
  verdict operation MUST return allow whenever the memory-pressure component
  alone would also allow — it MUST NOT block or defer solely because the
  size lookup failed.
- **warn-tier-log-emission**: When the computed tier is warn, the verdict
  operation MUST emit exactly one notice-level diagnostic log entry naming
  the model and its estimated resident footprint, marked as safe for public
  disclosure.
- **warn-tier-log-scope**: The verdict operation MUST NOT emit the warn-tier
  log for an ok or block tier, and MUST NOT emit it when the tier is unknown
  (size unavailable).
- **verdict-computation-delegation**: The verdict operation MUST compute its
  returned verdict by delegating to the model-fit policy, passing the
  injected memory monitor's current physical RAM and pressure level at the
  time of the call.
- **verdict-independent-of-exclusive-lock**: The verdict operation MUST be
  callable, and MUST be able to complete, without acquiring or waiting on
  the exclusive-run mutex — it reads and touches neither the busy flag nor
  the waiter queue.
- **pressure-only-recheck**: The pressure-only recheck operation MUST
  return the model-fit policy's pressure-only verdict, evaluated fresh
  against the memory monitor's current pressure level rather than any value
  cached from a prior verdict call, so it can be re-checked once inside a
  held lock's critical section.
- **mutual-exclusion**: The exclusive-run operation MUST guarantee that at
  most one operation is running at any instant across all concurrent callers
  of one guard instance.
- **fifo-admission-order**: Acquirers that begin waiting while the guard is
  busy MUST be granted ownership in the order they began waiting; a later
  arrival MUST NOT run its operation before an earlier, still-eligible
  waiter.
- **uncontended-fast-path**: A call to the exclusive-run operation made
  while no operation is running MUST proceed without parking — no waiter
  entry is created, and the busy flag is set directly.
- **direct-handoff-without-busy-gap**: On completing an operation, release
  MUST hand ownership directly to the head of the waiter queue when one
  exists, and the busy flag MUST remain set throughout that handoff; the
  busy flag MUST become unset only when the waiter queue is empty at release
  time.
- **post-acquire-cancellation-check**: Immediately after acquiring ownership
  and before the operation is invoked, the exclusive-run operation MUST
  check the calling operation's cancellation state and MUST fail with a
  cancellation error, without ever invoking the operation, if the caller was
  already cancelled.
- **release-on-every-exit-path**: The exclusive-run operation MUST release
  exactly once for every successful acquire, whether the operation returns
  normally, throws, the post-acquire cancellation check fails, or the
  deadline expires.
- **parked-cancellation-throws**: A waiter cancelled while still parked in
  the queue MUST be removed from the queue and MUST cause its acquire call
  to fail with a cancellation error, without ever invoking the operation.
- **handoff-race-cancellation-noop**: If a waiter's cancellation is observed
  after release has already removed that waiter from the queue and resumed
  it as the new owner, that cancellation MUST be a no-op; only that owner's
  own subsequent cancellation check MAY still fail and release the lock.
- **default-deadline-value**: The exclusive-run operation MUST apply a
  default deadline of 600 seconds as the wall-clock bound on one operation
  when the caller supplies no deadline argument.
- **deadline-enforced-per-operation**: When the operation has not completed
  before the deadline elapses, the exclusive-run operation MUST cancel the
  operation and MUST fail with a deferred refusal naming the deadline in
  whole seconds, rather than continuing to wait or failing with a bare
  cancellation error.
- **deadline-clamped-to-nonnegative**: A deadline value less than or equal
  to zero MUST be treated as an immediate (zero-duration) timeout rather
  than producing a negative sleep duration.
- **deadline-cancellation-preserves-handoff**: When a deadline expiry
  cancels an operation, release MUST still run afterward and hand the lock
  to the next waiter (if any), exactly as on a normal completion.
- **operation-result-propagation**: The exclusive-run operation MUST return
  the operation's value to the caller unchanged when it completes before the
  deadline, and MUST propagate any error the operation raises unchanged (not
  wrapped) when it fails before the deadline.
- **concurrency-safe-operation-and-result**: The operation and its result
  MUST be safe to run and return across the concurrent execution the guard
  uses internally to race the operation against the deadline timer.
- **no-reentrant-acquisition**: The exclusive-run operation SHOULD NOT be
  called again on the same guard instance from within an operation it is
  already running for, because the mutex provides no reentrancy detection
  and the nested call parks behind itself with no deadline covering the time
  spent waiting to acquire (only time spent running an already-granted
  operation is deadline-bound).

## Appearance

Not applicable — this is a memory guard and process-wide inference mutex,
not a visual component.

## States

Not applicable — this is a memory guard and process-wide inference mutex,
not a visual component.

## Accessibility

Not applicable — this is a memory guard and process-wide inference mutex,
not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| local-inference-guard-001 | guard-refusal-cases, guard-refusal-description | Read the description of a blocked refusal carrying reason `"x"`, and of a deferred refusal carrying reason `"y"`. | Both return the associated reason unchanged: `"x"` and `"y"` respectively. |
| local-inference-guard-002 | guard-refusal-non-transport | Inspect the daemon's completion path where it consults the guard. | Both throw sites propagate the guard's blocked/deferred refusal directly — never wrapped in the daemon's own completion error type — so the CLI fallback path is never reached from either throw. |
| local-inference-guard-003 | shared-default-instance, injectable-dependencies | The shared default instance vs. a test-constructed guard built from a fixed-fetcher model catalog and a fixed memory monitor. | The injectable constructor accepts substitute catalog/memory values and every test runs with no live system memory monitor or network access. |
| local-inference-guard-004 | threshold-settings-override, threshold-fallback-on-missing-or-invalid, disk-size-lookup-delegation, verdict-computation-delegation | A verdict request for model `"big:latest"` (51 GB on disk), RAM 64 GB, a settings reader that returns no value for either threshold key, pressure normal. | A block verdict — est. resident 61.2 GB ≈ 95.6% of RAM, at or above the default 50% block threshold. |
| local-inference-guard-005 | threshold-settings-override | Same model/RAM, a settings reader that returns `"99"` for the block-threshold key and no value otherwise. | Allow — 95.6% is below the overridden 99% block threshold. |
| local-inference-guard-006 | threshold-fallback-on-missing-or-invalid | A verdict request with the same 51 GB / 64 GB setup as vector 004, but a settings reader that returns `"not-a-number"` for the block-threshold key. | Parsing the override fails, so the default 50% block threshold applies — outcome block, matching vector 004. |
| local-inference-guard-007 | unknown-size-fail-open, disk-size-lookup-delegation | A verdict request where the size lookup fails, pressure normal. | Allow — an unavailable disk size yields no tier, and the pressure component alone allows. |
| local-inference-guard-008 | verdict-computation-delegation | A verdict request where the size lookup fails, pressure critical. | Deferred, even though the size is unknown — pressure is checked ahead of the size tier. |
| local-inference-guard-009 | pressure-only-recheck | Call the pressure-only recheck operation directly with the memory monitor's pressure level set to warning, then to normal. | Returns a deferred verdict with reason "memory pressure is warning; deferring local inference" for warning, and allow for normal — independent of any model or disk-size input. |
| local-inference-guard-010 | warn-tier-log-emission, warn-tier-log-scope | Run a verdict request with a disk size landing in the warn band under default thresholds (e.g. 20 GB on 64 GB RAM ⇒ est. 24 GB ≈ 37.5% of RAM). | Exactly one notice-level log entry fires, naming the model and its estimated footprint; a repeat call with a size in the ok or block band, or with size unavailable, emits no such log line. |
| local-inference-guard-011 | verdict-independent-of-exclusive-lock, mutual-exclusion, serialized-mutable-state | While an exclusive-run operation is in flight (holding the lock) on one guard instance, call the verdict operation concurrently on the same instance. | The verdict operation returns without waiting for the in-flight operation to complete or release the lock. |
| local-inference-guard-012 | mutual-exclusion, serialized-mutable-state | Four concurrent exclusive-run calls, each sleeping 20ms while an overlap tracker records concurrency. | The tracker's maximum observed concurrency is 1. |
| local-inference-guard-013 | fifo-admission-order, direct-handoff-without-busy-gap | One holder plus three waiters parked in order, released in sequence. | The waiters run in the order they arrived: first, second, third. |
| local-inference-guard-014 | uncontended-fast-path | Call the exclusive-run operation on an idle guard with no operation in flight. | The operation runs immediately with a waiter count of zero throughout — no waiter entry is ever created. |
| local-inference-guard-015 | post-acquire-cancellation-check, release-on-every-exit-path | Call the exclusive-run operation from a caller already cancelled before the call starts, on an otherwise idle guard. | The cancellation check fails immediately after the uncontended acquire succeeds; the operation never runs; release still runs, leaving the busy flag unset. |
| local-inference-guard-016 | parked-cancellation-throws | A waiter parked in the queue is cancelled before the holder finishes. | The cancelled waiter's result is a cancellation failure, its operation never ran, and the waiter count drops to zero immediately — without waiting for the holder to finish. |
| local-inference-guard-017 | handoff-race-cancellation-noop | Cancel a waiter at the instant release has already removed it from the queue and resumed it as the new owner. | The cancellation finds no matching waiter in the queue and is a no-op; the waiter proceeds as the new owner. |
| local-inference-guard-018 | default-deadline-value | Call the exclusive-run operation with no deadline argument. | The default deadline (600 seconds) is the value used to bound the operation. |
| local-inference-guard-019 | deadline-enforced-per-operation, deadline-cancellation-preserves-handoff | A deadline of 0.1s, a hung operation sleeping 60s, a second waiter queued behind it. | The waiter's exclusive-run call resolves well before 60s; the hung operation's result is a deferred refusal. |
| local-inference-guard-020 | deadline-clamped-to-nonnegative | An exclusive-run call with a deadline of -5.0 seconds. | Clamping the deadline to zero yields a zero-duration timeout rather than a negative-duration crash — the timeout fires essentially immediately. |
| local-inference-guard-021 | operation-result-propagation | An exclusive-run call whose operation throws, and, separately, one whose operation returns a value, on an idle guard with a large deadline. | The thrown error propagates unchanged in the first case; the returned value is returned unchanged in the second. |
| local-inference-guard-022 | concurrency-safe-operation-and-result | Attempt an exclusive-run call whose operation returns a value of a type that is not safe to share across the guard's internal concurrent execution. | Rejected before the operation can run — the guard requires its operation and result to be safe for that concurrent execution. |
| local-inference-guard-024 | no-reentrant-acquisition | An exclusive-run operation that itself calls exclusive-run again on the same guard instance from within its own operation. | The inner call parks behind the outer call (the busy flag is already set); since only the outer operation's completion can release the lock, and the outer operation is itself suspended awaiting the inner call, neither call ever completes. |

## Edge Cases

- **Null and empty input**: An empty model name or base URL is not
  special-cased by the verdict operation; it is forwarded to the model
  catalog's size lookup, which is expected to yield "unknown" (unknown
  size), so the verdict operation MUST fall through to the unknown-size,
  fail-open path exactly as for any other unrecognized model (MUST). A
  settings reader that returns no value for either threshold key MUST fall
  back to the documented 25%/50% defaults (MUST, see
  `threshold-fallback-on-missing-or-invalid`).
- **Boundary values**: A deadline of exactly `0` or negative MUST be clamped
  to a zero-duration timer rather than crash (MUST, see
  `deadline-clamped-to-nonnegative`). Because the deferred-reason message
  truncates the deadline toward zero when formatting it as whole seconds,
  any deadline under one second (e.g. a test's `0.1`) reads as `"...its 0s
  deadline..."` in the thrown reason string — a direct, undocumented-
  elsewhere consequence of that truncation that this recipe records rather
  than idealizes. The warn/block percentage values read from settings are
  forwarded to the model-fit policy unclamped; the guard itself performs no
  range validation (e.g. rejecting a negative or >100 percentage) on these
  values.
- **Concurrent access**: Concurrent exclusive-run callers on one instance
  MUST be serialized to at most one running operation at a time, in FIFO
  admission order (MUST, see `mutual-exclusion`, `fifo-admission-order`).
  The verdict and pressure-only recheck operations do not touch the busy
  flag or waiter queue, so they MUST remain callable, and MUST be able to
  complete, at any time — including while another call holds the exclusive
  lock (MUST, see `verdict-independent-of-exclusive-lock`). Calling the
  exclusive-run operation reentrantly on the same instance from within an
  operation it is already running for is not detected and deadlocks with no
  time bound, since the deadline only covers time spent running a granted
  operation, never time spent waiting to acquire the lock (SHOULD NOT, see
  `no-reentrant-acquisition`).
- **Error states**: If the model catalog's size lookup cannot determine a
  size (an unreachable or unrecognized local server), the verdict operation
  treats that identically to a model it has never seen — size unavailable,
  fail-open under normal pressure (MUST, see `unknown-size-fail-open`). If
  the operation inside an exclusive run fails before its deadline elapses,
  that exact error MUST propagate to the caller and the deadline timer MUST
  be cancelled without effect (MUST, see `operation-result-propagation`).
- **Offline or disconnected state**: The guard makes no network call of its
  own; an unreachable local model server is observed only indirectly, as the
  model catalog's size lookup returning "unavailable," and is handled
  identically to any other unknown-size case above. The verdict operation
  itself never fails and is never cancellation-checked, so if the calling
  operation is cancelled while the verdict operation awaits the size
  lookup, the verdict operation still completes and returns an ordinary
  verdict (typically allow) rather than raising a cancellation error — this
  is a direct consequence of the verdict operation's non-failing contract,
  not a bug.
- **Cancellation and timeouts**: A waiter cancelled while parked MUST fail
  its acquire call with a cancellation error without ever running the
  operation (MUST, see `parked-cancellation-throws`). An operation that
  exceeds its deadline MUST be cancelled and reported as a deferred refusal,
  and the lock MUST still be handed off to the next waiter afterward (MUST,
  see `deadline-enforced-per-operation`, `deadline-cancellation-preserves-
  handoff`). A caller's own cancellation, checked once immediately after
  acquire succeeds, MUST prevent the operation from ever running for that
  call (MUST, see `post-acquire-cancellation-check`).
- **Missing file or unreachable server**: Not directly observable inside the
  guard itself — a missing local model file or an unreachable server
  surfaces only as the model catalog's size lookup returning "unavailable,"
  handled as described under Error states and Offline/disconnected state
  above.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `catalog` (constructor parameter) | model catalog | production catalog | Injectable model-size lookup; tests substitute a fixed or failing fetcher. |
| `memory` (constructor parameter) | memory monitor | production monitor | Injectable RAM/pressure source; tests substitute a fixed value. |
| `deadline` (parameter to the exclusive-run operation) | duration | 600 seconds | Wall-clock bound on one exclusive operation's run. |
| `model`, `baseURL` (parameters to the verdict operation) | string, string | none — required | Identify the candidate local model and its loopback server. |
| `settings` (parameter to the verdict operation) | settings reader | none — required | Host-supplied reader for the `ai_guard_warn_pct` / `ai_guard_block_pct` override keys (declared on the model-fit policy, not this component). |
| `operation` (parameter to the exclusive-run operation) | the work to run | none — required | The local-inference work to run under the process-wide exclusive lock. |

The guard defines no environment variable of its own; the two settings keys
it reads (`ai_guard_warn_pct`, `ai_guard_block_pct`) are declared on the
sibling model-fit policy and reached only through the caller-supplied
settings reader.

## Deep Linking

Not applicable: the guard defines no URL scheme, route, or navigation
destination — it is a process-internal memory guard and mutex, not app
navigation.

## Localization

The guard defines no string-key or localization-table lookup; every string
it produces is a hardcoded English literal composed inline, with no key
system to reference:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Local model <model> is warn-tier: <footprint> est.` | The verdict operation's notice-level log entry when the computed tier is warn. |
| (none — literal, no key) | `local inference exceeded its <N>s deadline; deferring` | The deadline timer's expiry path, surfaced to callers as the deferred refusal's description. |

## Accessibility Options

Not applicable: the guard presents no UI, so it responds to no Reduce
Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: the guard defines no feature-flag or on/off settings-key
gate of its own; the `ai_guard_warn_pct` / `ai_guard_block_pct` keys it
reads via the settings reader are numeric thresholds (see Configuration),
not a flag that enables or disables the guard.

## Analytics

Not applicable: the guard contains no analytics or event-tracking call.

## Privacy

Not applicable: the guard handles only a model name and a loopback base
URL — configuration values identifying a local model server — and touches
no credential, token, or personal data; secret handling belongs to the
host's own secret storage and daemon, not this component.

## Logging

Subsystem: `com.agentic-cookbook.AIPluginKit` | Category: `LocalInferenceGuard`

| Event | Level | Message |
|-------|-------|---------|
| A `verdict` call's computed tier is `.warn` | notice | `Local model <model> is warn-tier: ~<X> GB (~<Y>% of RAM) est.` |

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/AIPluginKit/LocalInferenceGuard.swift`,
  alongside its collaborators `ModelFitPolicy.swift`,
  `LocalModelCatalog.swift`, and `SystemMemoryMonitor.swift`, and its
  consumer `DaemonAIChat.swift`/`DaemonProviderResolver.swift` (the source of
  `ProviderSettingsReader`). `LocalInferenceGuard` is declared as an `actor`,
  so its mutable state (`busy`, `waiters`) is serialized by the actor's own
  executor rather than by a manual lock; the mutex and deadline race are
  built from `CheckedContinuation` and `withThrowingTaskGroup`, with a
  post-acquire `Task.checkCancellation()` check, `defer`-guaranteed
  `release()` on every exit path, and a `CancellationError` thrown for both
  a cancelled parked waiter and a caller cancelled before/at acquire.
  `runExclusive<T: Sendable>` requires its `operation` closure to be
  `@Sendable` and `T` to conform to `Sendable`, since `operation` runs
  inside a `Task` racing the deadline-timer task; attempting
  `runExclusive { NSMutableString() }` (a non-`Sendable` return type) in a
  strict-concurrency build fails to compile. `waiterCount` carries no
  `public`/`private` modifier (Swift's default `internal`), so it functions
  as a test seam reachable only via `@testable import` without becoming
  part of the type's public API. It uses `os.Logger` for logging
  (subsystem `com.agentic-cookbook.AIPluginKit`, category
  `LocalInferenceGuard`, `privacy: .public` on the warn-tier message), and
  `DispatchSourceMemoryPressure` (via `SystemMemoryMonitor`) for live
  pressure. Nothing here is SwiftUI-specific — any host consumes
  `LocalInferenceGuard` identically.
- **Compose**: Kotlin has a ready FIFO-fair primitive
  (`kotlinx.coroutines.sync.Mutex`) to stand in for the hand-rolled
  continuation queue, and `withTimeoutOrNull`/`withTimeout` from
  kotlinx-coroutines in place of the manual `TaskGroup` deadline race.
  `ActivityManager.MemoryInfo`/`ComponentCallbacks2.onTrimMemory` is the
  Android analogue of `SystemMemoryMonitoring`'s latched pressure level; a
  plain `object`/singleton class stands in for `LocalInferenceGuard.shared`.
- **React/Web**: Neither Node.js nor the browser exposes an OS-level
  memory-pressure signal analogous to `DispatchSourceMemoryPressure`; a Node
  host can approximate available headroom with `os.totalmem()` /
  `process.memoryUsage()` but has no `.warning`/`.critical` latch to read. Use
  an async mutex library (e.g. `async-mutex`'s `Mutex`, which is FIFO by
  default) for the exclusive lock, `AbortController` plus `Promise.race`
  against a `setTimeout` for the deadline race in place of
  `withThrowingTaskGroup`, and `fetch` with `AbortSignal.timeout(5000)` for
  the model-size lookup analogous to `LocalModelCatalog.liveFetcher`.
- **AppKit / UIKit**: Identical to the SwiftUI note — this actor is
  UI-framework-agnostic; only the host application embedding `AIPluginKit`
  differs, never this contract.
- **WinUI 3**: Model `LocalInferenceGuard` as a plain C# class wrapping a
  `SemaphoreSlim(1, 1)` (FIFO-fair by default) in place of the hand-rolled
  `CheckedContinuation` waiter queue, exposing an `async Task<T>
  RunExclusiveAsync<T>(TimeSpan deadline, Func<Task<T>> operation)` method.
  Race the deadline with `Task.WhenAny(operationTask,
  Task.Delay(deadline, cts.Token))` and a `CancellationTokenSource` in place
  of `withThrowingTaskGroup`, cancelling the loser exactly as the source
  does. Represent `AIGuardError` as two distinct exception types (e.g.
  `AiGuardBlockedException` / `AiGuardDeferredException`), never a subtype or
  wrapper of whatever exception carries transport failures, so a `catch`
  block for the CLI-style fallback path structurally cannot also catch a
  guard refusal. Use `GlobalMemoryStatusEx` (via P/Invoke) or
  `Windows.System.MemoryManager.AppMemoryUsageLevel` for the RAM/pressure
  analogue of `SystemMemoryMonitoring`, and `HttpClient` with a 5-second
  `Timeout` for the model-size fetch analogous to
  `LocalModelCatalog.liveFetcher`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/LocalInferenceGuard.swift` |

## Design Decisions

**Decision**: `runExclusive`'s `deadline` bounds only the operation's own
execution once the lock is granted, not the time spent waiting to acquire
it.
**Rationale**: The doc comment states this explicitly — "`deadline` bounds
the operation's wall-clock run." Because the raw `acquire`/`release`/
`cancelWaiter` primitives are private, every caller reaches the lock only
through `runExclusive`, so every current holder is itself deadline-bound;
this gives every waiter an implicit, transitive bound on total wait time
without needing an explicit per-waiter timeout.
**Approved**: pending

**Decision**: The mutex is not reentrant, and `runExclusive` performs no
recursion or owner-task detection.
**Rationale**: This matches the semantics of a plain `NSLock`/
`DispatchSemaphore`; adding owner-task bookkeeping was not implemented, and
every current call site (`DaemonAIChat.complete`/`completeViaPlugin`) calls
`runExclusive` exactly once per request, so a self-deadlock from reentrant
use is a documented caller obligation (see `no-reentrant-acquisition`) rather
than a runtime-enforced one.
**Approved**: pending

**Decision**: `release()` hands ownership directly to the next waiter,
keeping `busy` `true` across the handoff rather than briefly setting it
`false` and letting a new caller re-acquire.
**Rationale**: Per the source comment: "Direct handoff: the head waiter
becomes the owner; `busy` never dips to false in between, so no arrival can
slip past the queue." A false-then-true toggle would open a race window in
which a brand-new, uncontended caller could acquire ahead of an
already-waiting FIFO queue.
**Approved**: pending

**Decision**: The deferred-reason message composes the deadline with
`Int(deadline)`, which truncates toward zero.
**Rationale**: This is a direct, unremarked consequence of Swift's
`Int(Double)` conversion at the message-formatting call site; the guard does
not round or special-case sub-second deadlines (e.g. the test suite's
`deadline: 0.1` reads as `"...its 0s deadline..."`), and no production host
currently configures a sub-second deadline.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | partial | Reliability |

Notes: separation-of-concerns passes because verdict computation is delegated entirely to `ModelFitPolicy.verdict`, RAM and pressure are delegated to the injected `SystemMemoryMonitoring`, and the exclusive-run mutex is kept independent of the verdict path (`verdict-independent-of-exclusive-lock`). unit-test-coverage passes because `LocalInferenceGuardTests.swift` exercises thresholds, FIFO ordering, deadlines, and cancellation directly across 24 vectors. explicit-error-handling passes because a guard refusal is raised as a distinct `AIGuardError` type kept deliberately separate from `DaemonAIChat.ChatError`, so it is never silently reinterpreted as a transport failure (`guard-refusal-non-transport`). timeout-handling passes because a deadline expiry cancels the operation and still runs `release()` afterward, handing the lock to the next waiter and leaving the mutex in a consistent state (`deadline-enforced-per-operation`, `deadline-cancellation-preserves-handoff`). graceful-degradation passes because an unknown model size — the `LocalModelCatalog` size lookup returning `nil` — fails open to `.allow` under normal pressure rather than blocking or crashing (`unknown-size-fail-open`). health-observability is partial because `verdict` emits one `notice`-level log only when the computed tier is `.warn`, with no equivalent signal for the mutex's own long-lived state, such as waiter-queue depth or contention.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/models/local/. |
