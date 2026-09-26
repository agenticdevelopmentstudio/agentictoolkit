---
id: 8d827e9d-3638-4eaf-b04b-223b29b53389
title: LocalInferenceGuard
domain: agentictoolkit://cookbook/ai-plugin-kit/local-inference-guard
type: ingredient
version: 1.0.3
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Actor guarding local-model inference: verdicts requests against RAM/pressure
  and serializes runs behind a FIFO async mutex with a deadline.'
platforms:
- swift
- macos
tags:
- ai-plugin
- memory-guard
- local-inference
- concurrency
- actor
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

# LocalInferenceGuard

## Overview

`LocalInferenceGuard` is the actor-isolated memory guard `AIPluginKit`'s
`DaemonAIChat` consults before dispatching a chat request to a loopback
("local") model server. Given a model name and base URL,
`verdict(model:baseURL:settings:)` asks `LocalModelCatalog` for the model's
on-disk size, asks the injected `SystemMemoryMonitoring` for the machine's
physical RAM and latched memory-pressure level, and returns a
`ModelFitPolicy.Verdict` (`.allow`, `.block(reason:)`, or
`.deferred(reason:)`). Independently of that verdict,
`runExclusive(deadline:_:)` serializes local inference process-wide behind a
single async mutex, so two host features that each trigger a local model load
(e.g. summaries and oversight) cannot do so at once; the mutex is a FIFO queue
of parked acquirers with direct-handoff release, and each exclusive run is
bounded by a wall-clock `deadline` (600s by default) after which the operation
is cancelled and the guard reports `AIGuardError.deferred`. `AIGuardError`
(`.blocked`/`.deferred`) is a distinct error type from `DaemonAIChat`'s own
`ChatError`: per the source's own comment, a guard refusal is "terminal for
this attempt" and must never be reinterpreted as a transport failure eligible
for the `claude -p` CLI fallback.

## Behavioral Requirements

- **guard-refusal-cases**: `AIGuardError` MUST provide exactly two cases,
  `.blocked(String)` and `.deferred(String)`, each carrying a human-readable
  reason string.
- **guard-refusal-description**: `AIGuardError.errorDescription` MUST return
  the associated reason string unchanged for both `.blocked` and `.deferred`.
- **guard-refusal-non-transport**: A guard refusal (`.blocked` or
  `.deferred`) MUST NOT be treated by a caller as a transport failure eligible
  for another provider path; per the doc comment, it is "Deliberately NOT a
  `DaemonAIChat.ChatError`... it must never cascade into the `claude -p`
  fallback."
- **shared-default-instance**: `LocalInferenceGuard.shared` MUST provide one
  process-wide default instance, constructed from the production dependencies
  `LocalModelCatalog.shared` and `SystemMemoryMonitor.shared`.
- **injectable-dependencies**: `init(catalog:memory:)` MUST accept a
  substitutable `LocalModelCatalog` and `any SystemMemoryMonitoring`, each
  defaulting to its production singleton, so a caller MAY construct a guard
  backed by fixed or fake behavior.
- **actor-isolated-mutable-state**: `LocalInferenceGuard` MUST be declared as
  an `actor`, so its mutable state (`busy`, `waiters`) is serialized by the
  actor's own executor rather than by a manual lock.
- **threshold-settings-override**: `verdict(model:baseURL:settings:)` MUST
  read the warn and block percentage thresholds from `settings` under
  `ModelFitPolicy.warnPctKey` and `ModelFitPolicy.blockPctKey` and MUST use
  the parsed integer when one is present.
- **threshold-fallback-on-missing-or-invalid**: `verdict` MUST fall back to
  `ModelFitPolicy.defaultWarnPct` (25) / `ModelFitPolicy.defaultBlockPct` (50)
  when `settings` returns `nil` for a threshold key, or returns a string that
  is not parseable as an `Int`.
- **disk-size-lookup-delegation**: `verdict` MUST obtain the candidate
  model's on-disk size by calling `catalog.sizeBytes(model:baseURL:)`, and
  MUST treat a `nil` result as "size unknown" rather than substituting a
  default size.
- **unknown-size-fail-open**: When the disk size is unknown (tier is `nil`),
  `verdict` MUST return `.allow` whenever the memory-pressure component alone
  would also allow — it MUST NOT block or defer solely because the size
  lookup failed.
- **warn-tier-log-emission**: When the computed tier is `.warn`, `verdict`
  MUST emit exactly one `notice`-level log via `Logger` (subsystem
  `com.agentic-cookbook.AIPluginKit`, category `LocalInferenceGuard`) naming
  the model and its estimated resident footprint, with `privacy: .public`.
- **warn-tier-log-scope**: `verdict` MUST NOT emit the warn-tier log for an
  `.ok` or `.block` tier, and MUST NOT emit it when the tier is `nil`
  (size unknown).
- **verdict-computation-delegation**: `verdict` MUST compute its returned
  `ModelFitPolicy.Verdict` by calling
  `ModelFitPolicy.verdict(model:diskBytes:physicalRAM:warnPct:blockPct:pressure:)`,
  passing the injected memory monitor's current `physicalRAM` and
  `pressureLevel` at the time of the call.
- **verdict-independent-of-exclusive-lock**: `verdict` MUST be callable, and
  MUST be able to complete, without acquiring or waiting on the
  `runExclusive` mutex — it reads and touches neither `busy` nor `waiters`.
- **pressure-only-recheck**: `pressureVerdict()` MUST return
  `ModelFitPolicy.pressureVerdict(memory.pressureLevel)`, evaluated fresh
  against the memory monitor's current pressure level rather than any value
  cached from a prior `verdict()` call, so it can be re-checked once inside a
  held lock's critical section.
- **mutual-exclusion**: `runExclusive(deadline:_:)` MUST guarantee that at
  most one `operation` closure is running at any instant across all
  concurrent callers of one `LocalInferenceGuard` instance.
- **fifo-admission-order**: Acquirers that begin waiting while the guard is
  busy MUST be granted ownership in the order they began waiting; a later
  arrival MUST NOT run its operation before an earlier, still-eligible
  waiter.
- **uncontended-fast-path**: A call to `runExclusive` made while no operation
  is running MUST proceed without parking — no continuation is created, and
  `busy` is set directly.
- **direct-handoff-without-busy-gap**: On completing an operation,
  `release()` MUST hand ownership directly to the head of the waiter queue
  when one exists, and `busy` MUST remain `true` throughout that handoff;
  `busy` MUST become `false` only when the waiter queue is empty at release
  time.
- **post-acquire-cancellation-check**: Immediately after `acquire()` returns
  and before `operation` is invoked, `runExclusive` MUST check the calling
  task's cancellation via `Task.checkCancellation()` and MUST throw
  `CancellationError` without ever invoking `operation` if the calling task
  was already cancelled.
- **release-on-every-exit-path**: `runExclusive` MUST call `release()`
  exactly once for every successful `acquire()`, whether `operation` returns
  normally, throws, the post-acquire cancellation check throws, or the
  deadline expires — via `defer`.
- **parked-cancellation-throws**: A waiter cancelled while still parked in
  the queue MUST be removed from the queue and MUST cause its `acquire()`
  call to throw `CancellationError`, without ever invoking `operation`.
- **handoff-race-cancellation-noop**: If a waiter's cancellation handler runs
  after `release()` has already removed that waiter from the queue and
  resumed it as the new owner, the cancellation handler MUST be a no-op; only
  that owner's own subsequent `Task.checkCancellation()` call MAY still throw
  and release the lock.
- **default-deadline-value**: `runExclusive` MUST apply
  `LocalInferenceGuard.defaultDeadline` (600 seconds) as the wall-clock bound
  on one operation when the caller supplies no `deadline` argument.
- **deadline-enforced-per-operation**: When `operation` has not completed
  before `deadline` elapses, `runExclusive` MUST cancel the operation's task
  and MUST throw `AIGuardError.deferred` naming the deadline in whole
  seconds, rather than continuing to wait or throwing a bare
  `CancellationError`.
- **deadline-clamped-to-nonnegative**: A `deadline` value less than or equal
  to zero MUST be treated as an immediate (zero-duration) timeout rather than
  producing a negative sleep duration.
- **deadline-cancellation-preserves-handoff**: When a deadline expiry cancels
  an operation, `release()` MUST still run afterward and hand the lock to the
  next waiter (if any), exactly as on a normal completion.
- **operation-result-propagation**: `runExclusive` MUST return `operation`'s
  value to the caller unchanged when it completes before the deadline, and
  MUST propagate any error `operation` throws unchanged (not wrapped) when it
  fails before the deadline.
- **sendable-operation-and-result**: `runExclusive<T: Sendable>` MUST require
  its `operation` closure to be `@Sendable` and its result type `T` to
  conform to `Sendable`, since `operation` runs inside a `Task` in a
  `withThrowingTaskGroup` racing concurrently against the deadline-timer
  task.
- **waiter-count-internal-visibility**: `waiterCount` MUST be visible only
  within the declaring module (no `public`/`private` modifier — Swift's
  default `internal`), so it functions as a test seam without becoming part
  of the type's public API.
- **no-reentrant-acquisition**: `runExclusive` SHOULD NOT be called again on
  the same `LocalInferenceGuard` instance from within an `operation` closure
  it is already running for, because the mutex provides no reentrancy
  detection and the nested call parks behind itself with no deadline covering
  the time spent waiting to acquire (only time spent running an already-
  granted `operation` is deadline-bound).

## Appearance

Not applicable — this is an actor-based memory guard and process-wide
inference mutex, not a visual component.

## States

Not applicable — this is an actor-based memory guard and process-wide
inference mutex, not a visual component.

## Accessibility

Not applicable — this is an actor-based memory guard and process-wide
inference mutex, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| local-inference-guard-001 | guard-refusal-cases, guard-refusal-description | `AIGuardError.blocked("x").errorDescription` and `AIGuardError.deferred("y").errorDescription` (`LocalInferenceGuard.swift`). | Both return the associated reason unchanged: `"x"` and `"y"` respectively. |
| local-inference-guard-002 | guard-refusal-non-transport | Inspect `DaemonAIChat.complete`/`completeViaPlugin` (`DaemonAIChat.swift`). | Both throw sites read `throw AIGuardError.blocked(reason)` / `.deferred(reason)` directly — never wrapped in `ChatError.providerError` — so `completeViaCLI` (the `claude -p` fallback) is never reached from either throw. |
| local-inference-guard-003 | shared-default-instance, injectable-dependencies | `LocalInferenceGuard.shared` vs. `LocalInferenceGuardTests.makeGuard(tags:pressure:)`, which builds `LocalInferenceGuard(catalog: LocalModelCatalog(fetcher: { ... }), memory: FixedMemory(...))` (`LocalInferenceGuardTests.swift`). | The injected initializer accepts substitute `catalog`/`memory` values and every test in the file runs with no live `SystemMemoryMonitor.shared` or network access. |
| local-inference-guard-004 | threshold-settings-override, threshold-fallback-on-missing-or-invalid, disk-size-lookup-delegation, verdict-computation-delegation | `blocksOverBudgetModel`: model `"big:latest"` (51 GB on disk), RAM 64 GB, `settings: { _ in nil }`, pressure `.normal` (`LocalInferenceGuardTests.swift`). | `.block` verdict — est. resident 61.2 GB ≈ 95.6% of RAM, at or above the default 50% block threshold. |
| local-inference-guard-005 | threshold-settings-override | `thresholdOverridesComeFromSettings`: same model/RAM, `settings: { key in key == ModelFitPolicy.blockPctKey ? "99" : nil }`. | `.allow` — 95.6% is below the overridden 99% block threshold. |
| local-inference-guard-006 | threshold-fallback-on-missing-or-invalid | `verdict(model: "big:latest", baseURL: ..., settings: { key in key == ModelFitPolicy.blockPctKey ? "not-a-number" : nil })` with the same 51 GB / 64 GB setup as vector 004 (`LocalInferenceGuard.swift`). | `Int.init("not-a-number")` fails, `flatMap` yields `nil`, so the default 50% block threshold applies — outcome `.block`, matching vector 004. |
| local-inference-guard-007 | unknown-size-fail-open, disk-size-lookup-delegation | `unknownSizeFailsOpen`: `tags: nil` (fetcher throws), pressure `.normal`. | `.allow` — `nil` diskBytes yields a `nil` tier, and the pressure component alone allows. |
| local-inference-guard-008 | verdict-computation-delegation | `defersUnderPressureEvenWithUnknownSize`: `tags: nil`, pressure `.critical`. | `.deferred`, even though the size is unknown — pressure is checked ahead of the size tier. |
| local-inference-guard-009 | pressure-only-recheck | Call `guardActor.pressureVerdict()` directly with the memory monitor's `pressureLevel` set to `.warning`, then to `.normal` (`LocalInferenceGuard.swift`). | Returns `.deferred(reason: "memory pressure is warning; deferring local inference")` for `.warning`, and `.allow` for `.normal` — independent of any model or disk-size input. |
| local-inference-guard-010 | warn-tier-log-emission, warn-tier-log-scope | Call `verdict` with a disk size landing in the warn band under default thresholds (e.g. 20 GB on 64 GB RAM ⇒ est. 24 GB ≈ 37.5% of RAM). | Exactly one `Logger.notice` call fires, naming the model and its estimated footprint; a repeat call with a size in the `.ok` or `.block` band, or with `nil` size, emits no such log line. |
| local-inference-guard-011 | verdict-independent-of-exclusive-lock, mutual-exclusion, actor-isolated-mutable-state | While a `runExclusive` operation is in flight (holding the lock) on `guardActor`, call `verdict(model:baseURL:settings:)` concurrently on the same instance. | `verdict` returns without waiting for the in-flight operation to complete or release the lock. |
| local-inference-guard-012 | mutual-exclusion, actor-isolated-mutable-state | `runExclusiveSerializes`: 4 concurrent `runExclusive` calls, each sleeping 20ms inside an `OverlapTracker`. | `tracker.maxConcurrent == 1`. |
| local-inference-guard-013 | fifo-admission-order, direct-handoff-without-busy-gap | `waitersRunInFIFOOrder`: one holder plus three waiters parked in order, released in sequence. | `order.values == [0, 1, 2]`. |
| local-inference-guard-014 | uncontended-fast-path | Call `runExclusive` on an idle guard with no operation in flight. | The operation runs immediately with `waiterCount == 0` throughout — no continuation is ever created. |
| local-inference-guard-015 | post-acquire-cancellation-check, release-on-every-exit-path | Call `runExclusive` from a `Task` cancelled before its body starts running, on an otherwise idle guard. | `Task.checkCancellation()` throws `CancellationError` immediately after the uncontended `acquire()` succeeds; `operation` never runs; `release()` still runs via `defer`, leaving `busy == false`. |
| local-inference-guard-016 | parked-cancellation-throws | `cancelledParkedWaiterThrowsWithoutRunning`. | The cancelled waiter's `result` is `.failure(CancellationError)`, `ran.isRaised == false`, and `waiterCount == 0` immediately — without waiting for the holder to finish. |
| local-inference-guard-017 | handoff-race-cancellation-noop | Cancel a waiter's `Task` at the instant `release()` has already called `waiters.removeFirst().continuation.resume(returning: true)` for it. | `cancelWaiter` finds no matching `id` in `waiters` and is a no-op; the waiter proceeds as the new owner. |
| local-inference-guard-018 | default-deadline-value | Call `runExclusive` with no `deadline` argument. | `LocalInferenceGuard.defaultDeadline` (600 seconds) is the value threaded into `withDeadline`. |
| local-inference-guard-019 | deadline-enforced-per-operation, deadline-cancellation-preserves-handoff | `deadlineCutsOffHungOperation`: `deadline: 0.1`, a hung operation sleeping 60s, a second waiter queued behind it. | The waiter's `runExclusive` resolves to `"ran"` well before 60s; the hung task's `result` is `.failure(AIGuardError.deferred)`. |
| local-inference-guard-020 | deadline-clamped-to-nonnegative | `runExclusive(deadline: -5.0) { "ok" }`. | `max(0, deadline)` yields a zero-duration sleep rather than a negative-duration crash — the timer branch fires essentially immediately. |
| local-inference-guard-021 | operation-result-propagation | `runExclusive { throw MyError() }` and, separately, `runExclusive { 42 }`, on an idle guard with a large deadline. | The thrown `MyError` propagates unchanged in the first case; `42` is returned unchanged in the second. |
| local-inference-guard-022 | sendable-operation-and-result | Attempt `runExclusive { NSMutableString() }` (a non-`Sendable` return type) in a strict-concurrency build. | Fails to compile — the `T: Sendable` generic constraint rejects a non-`Sendable` result type. |
| local-inference-guard-023 | waiter-count-internal-visibility | From `LocalInferenceGuardTests.swift` (`@testable import AIPluginKit`), read `guardActor.waiterCount` (used throughout). | Compiles and reads the live count; a module that only does `import AIPluginKit` (no `@testable`) fails to compile the same access, since `waiterCount` carries no `public` modifier. |
| local-inference-guard-024 | no-reentrant-acquisition | `runExclusive { try await sameGuard.runExclusive { "inner" } }` on the same `LocalInferenceGuard` instance. | The inner call parks behind the outer call (`busy` is already `true`); since only the outer operation's completion can call `release()`, and the outer operation is itself suspended awaiting the inner call, neither call ever completes. |

## Edge Cases

- **Null and empty input**: An empty `model` or `baseURL` string is not
  special-cased by `verdict`; it is forwarded to
  `catalog.sizeBytes(model:baseURL:)`, which is expected to yield `nil`
  (unknown size), so `verdict` MUST fall through to the unknown-size,
  fail-open path exactly as for any other unrecognized model (MUST). A
  `settings` closure that returns `nil` for both threshold keys MUST fall
  back to the documented 25%/50% defaults (MUST, see
  `threshold-fallback-on-missing-or-invalid`).
- **Boundary values**: A `deadline` of exactly `0` or negative MUST be
  clamped to a zero-duration timer rather than crash (MUST, see
  `deadline-clamped-to-nonnegative`). Because the deferred-reason message is
  built with `Int(deadline)` (truncation toward zero), any `deadline` under
  one second (e.g. the test's `0.1`) reads as `"...its 0s deadline..."` in
  the thrown reason string — a direct, undocumented-elsewhere consequence of
  `Int(Double)` truncation that this recipe records rather than idealizes.
  `warnPct`/`blockPct` values read from `settings` are forwarded to
  `ModelFitPolicy.verdict` unclamped; `LocalInferenceGuard.swift` itself
  performs no range validation (e.g. rejecting a negative or >100 percentage)
  on these values.
- **Concurrent access**: Concurrent `runExclusive` callers on one instance
  MUST be serialized to at most one running operation at a time, in FIFO
  admission order (MUST, see `mutual-exclusion`, `fifo-admission-order`).
  `verdict` and `pressureVerdict` are ordinary actor methods that do not
  touch `busy`/`waiters`, so they MUST remain callable, and MUST be able to
  complete, at any time — including while another call holds the exclusive
  lock (MUST, see `verdict-independent-of-exclusive-lock`). Calling
  `runExclusive` reentrantly on the same instance from within an operation it
  is already running for is not detected and deadlocks with no time bound,
  since the deadline only covers time spent running a granted `operation`,
  never time spent waiting inside `acquire()` (SHOULD NOT, see
  `no-reentrant-acquisition`).
- **Error states**: If `catalog.sizeBytes` cannot determine a size (an
  unreachable or non-ollama local server), `verdict` treats that identically
  to a model it has never seen — `nil` diskBytes, fail-open under normal
  pressure (MUST, see `unknown-size-fail-open`). If `operation` inside
  `runExclusive` throws before its deadline elapses, that exact error MUST
  propagate to the caller and the deadline timer MUST be cancelled without
  effect (MUST, see `operation-result-propagation`).
- **Offline or disconnected state**: `LocalInferenceGuard.swift` makes no
  network call of its own; an unreachable local model server is observed
  only indirectly, as `catalog.sizeBytes` returning `nil`, and is handled
  identically to any other unknown-size case above. `verdict` itself declares
  no `throws` and is never cancellation-checked, so if the calling task is
  cancelled while `verdict` awaits `catalog.sizeBytes`, `verdict` still
  completes and returns an ordinary `ModelFitPolicy.Verdict` (typically
  `.allow`) rather than raising `CancellationError` — this is a direct
  consequence of `verdict`'s non-throwing signature, not a bug.
- **Cancellation and timeouts**: A waiter cancelled while parked MUST throw
  `CancellationError` from `acquire()` without ever running `operation`
  (MUST, see `parked-cancellation-throws`). An operation that exceeds its
  `deadline` MUST be cancelled and reported as `AIGuardError.deferred`, and
  the lock MUST still be handed off to the next waiter afterward (MUST, see
  `deadline-enforced-per-operation`, `deadline-cancellation-preserves-
  handoff`). A caller's own task cancellation, checked once immediately after
  `acquire()` succeeds, MUST prevent `operation` from ever running for that
  call (MUST, see `post-acquire-cancellation-check`).
- **Missing file or unreachable server**: Not directly observable inside
  `LocalInferenceGuard.swift` — a missing local model file or an unreachable
  server surfaces only as `catalog.sizeBytes` returning `nil`, handled as
  described under Error states and Offline/disconnected state above.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `catalog` (parameter to `init`) | `LocalModelCatalog` | `.shared` | Injectable model-size lookup; tests substitute a fixed or failing fetcher. |
| `memory` (parameter to `init`) | `any SystemMemoryMonitoring` | `SystemMemoryMonitor.shared` | Injectable RAM/pressure source; tests substitute a fixed value (e.g. `FixedMemory`). |
| `deadline` (parameter to `runExclusive`) | `TimeInterval` | `LocalInferenceGuard.defaultDeadline` (600) | Wall-clock bound on one exclusive operation's run. |
| `model`, `baseURL` (parameters to `verdict`) | `String`, `String` | none — required | Identify the candidate local model and its loopback server. |
| `settings` (parameter to `verdict`) | `ProviderSettingsReader` (`@Sendable (String) -> String?`) | none — required | Host-supplied reader for the `ai_guard_warn_pct` / `ai_guard_block_pct` override keys (declared on `ModelFitPolicy`, not this file). |
| `operation` (parameter to `runExclusive`) | `@escaping @Sendable () async throws -> T` | none — required | The local-inference work to run under the process-wide exclusive lock. |

`LocalInferenceGuard.swift` defines no environment variable of its own; the
two settings keys it reads (`ModelFitPolicy.warnPctKey`,
`ModelFitPolicy.blockPctKey`) are declared on the sibling `ModelFitPolicy`
type and reached only through the caller-supplied `settings` closure.

## Deep Linking

Not applicable: `LocalInferenceGuard.swift` defines no URL scheme, route, or
navigation destination — it is a process-internal memory guard and mutex,
not app navigation.

## Localization

`LocalInferenceGuard.swift` defines no string-key or localization-table
lookup; every string it produces is a hardcoded English literal composed
inline, with no key system to reference:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Local model \(model) is warn-tier: \(footprint) est.` | `verdict(model:baseURL:settings:)`'s `Logger.notice` call when the computed tier is `.warn`. |
| (none — literal, no key) | `local inference exceeded its \(Int(deadline))s deadline; deferring` | `withDeadline`'s timer branch, surfaced to callers as `AIGuardError.deferred`'s `errorDescription`. |

## Accessibility Options

Not applicable: `LocalInferenceGuard.swift` presents no UI, so it responds to
no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `LocalInferenceGuard.swift` defines no feature-flag or
on/off settings-key gate of its own; the `ai_guard_warn_pct` /
`ai_guard_block_pct` keys it reads via `settings` are numeric thresholds (see
Configuration), not a flag that enables or disables the guard.

## Analytics

Not applicable: `LocalInferenceGuard.swift` contains no analytics or
event-tracking call.

## Privacy

Not applicable: `LocalInferenceGuard.swift` handles only a model name and a
loopback base URL — configuration values identifying a local model server —
and touches no credential, token, or personal data; secret handling belongs
to `SecretStoring`/`DaemonAIChat`, not this file.

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
  `ProviderSettingsReader`). It uses `actor` isolation plus
  `CheckedContinuation` and `withThrowingTaskGroup` for the mutex and
  deadline race, `os.Logger` for logging, and `DispatchSourceMemoryPressure`
  (via `SystemMemoryMonitor`) for live pressure. Nothing here is
  SwiftUI-specific — any host consumes `LocalInferenceGuard` identically.
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
