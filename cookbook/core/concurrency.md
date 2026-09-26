---
id: 4e06a00e-653a-4d29-81d8-ac6dccfedb6a
title: BlockingWork, KeyedDebouncer & PendingTeardowns
domain: agentictoolkit://cookbook/core/concurrency
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: BlockingWork's off-pool blocking hop, KeyedDebouncer's per-key debounce-with-retry,
  and PendingTeardowns' drainable teardown tracker.
platforms:
- swift
- macos
tags:
- concurrency
- foundation
- mainactor
- sendable
- debounce
- retry
- teardown
- gcd
depends-on: []
related:
- agentictoolkit://cookbook/core/extensions/extension-registry
- agentictoolkit://cookbook/core/extensions/vsix-installer
references: []
approved-by: ''
approved-date: ''
---

# BlockingWork, KeyedDebouncer & PendingTeardowns

## Overview

Three Foundation-only types in `packages/apple/AgenticToolkit/Core/Concurrency/`, part of the `AgenticToolkitCore` framework target, that each solve one recurring structured-concurrency mistake found independently at two or more call sites in this codebase. `BlockingWork` (`BlockingWork.swift`, a stateless `enum` namespace) hops a synchronous, thread-blocking closure onto a GCD global queue and resumes the calling `Task` with its result, so that work sitting on a semaphore or a large synchronous file read never occupies one of the cooperative thread pool's core-count threads. `KeyedDebouncer<Key>` (`KeyedDebouncer.swift`, an `@MainActor` generic `final class`) coalesces repeated per-key work into one debounced run and guarantees that a run which throws is never dropped: the entry stays pending and re-arms with exponential backoff until it succeeds or is explicitly cancelled. `PendingTeardowns` (`PendingTeardowns.swift`, an `@MainActor` `final class`) holds the task handle for teardown work started without a waiter, so a later shutdown path can `drain()` and be certain nothing it started is still in flight. None of the three performs any I/O of its own; each only manages *where* or *when* a caller-supplied closure runs.

## Behavioral Requirements

- **blocking-queue-hop**: `BlockingWork.run` (both overloads) MUST execute `work` on a GCD global queue (`DispatchQueue.global(qos:)`), never on the Swift concurrency cooperative thread pool that ordinary `Task`/`Task.detached` work shares (`BlockingWork.swift`).
- **blocking-qos-default**: Both `run` overloads MUST default their `qos` parameter to `.userInitiated` when the caller omits it.
- **blocking-throwing-resume**: The throwing overload MUST resume the caller with whatever value `work` returned, or rethrow whatever error `work` threw, via `continuation.resume(with: Result { try work() })`.
- **blocking-nonthrowing-resume**: The non-throwing overload MUST resume the caller with exactly the value `work` returned, with no error path.
- **blocking-sendable-boundary**: On both overloads, the generic result type `T` and the `work` closure itself MUST both be constrained to `Sendable`, because the value crosses a thread boundary once into the closure's execution context and once back out through the continuation.
- **blocking-not-a-cancellation-point**: `BlockingWork.run` MUST NOT observe or react to cancellation of the calling `Task` once `work` has been dispatched — the continuation resumes only when the synchronous `work` closure itself returns or throws, per the doc comment "nothing here can interrupt a synchronous call that is already running"; a caller needing bounded execution MUST give `work` its own deadline, the way `CommandRunner` does.
- **blocking-calls-run-independently**: Two or more concurrent calls to `BlockingWork.run` MUST run independently of one another with no shared state and no coordination between them — `BlockingWork` is a case-less `enum` holding no instance or static mutable state, so any number of calls MAY execute in parallel, each on whatever thread GCD's global queue grows to serve it.
- **debouncer-mainactor-isolation**: `KeyedDebouncer` MUST be declared `@MainActor` (`KeyedDebouncer.swift`), so every one of its methods and computed properties (`schedule`, `cancel`, `cancelAll`, `flush`, `flushAll`, `pendingKeys`, `isPending`) MUST run on, and only be callable from, the main actor.
- **debouncer-key-constraint**: `KeyedDebouncer`'s generic parameter `Key` MUST conform to `Hashable & Sendable`.
- **debounce-window-default**: `init` MUST default `debounce` to `.seconds(1)` when the caller omits it.
- **retry-ceiling-default-and-floor**: `init` MUST default `maximumRetryInterval` to `.seconds(30)` and MUST clamp the stored ceiling to be at least `debounce`, via `max(debounce, maximumRetryInterval)` — a caller passing a `maximumRetryInterval` smaller than `debounce` MUST NOT be rejected; the smaller value is silently raised to `debounce` instead.
- **schedule-coalesces-latest**: `schedule(key:_:)` MUST replace whatever work was previously scheduled for `key` with the new closure and MUST restart the debounce window from the moment of the call — only the most recently scheduled closure for a key is ever run, never a queue of every call.
- **schedule-during-run-defers-timer**: Calling `schedule(key:_:)` while `key`'s work is already running MUST NOT cancel that run and MUST NOT start a second run for the same key; it MUST record the newer work by bumping the entry's `generation` and resetting its `failures` to zero, and MUST cancel any armed timer without re-arming it until the running work finishes.
- **one-run-per-key**: `KeyedDebouncer` MUST NOT run more than one instance of a given key's work concurrently — `beginRun(key:)` MUST return without effect when that key's `entry.run` is already non-nil.
- **cross-key-concurrency**: Work for two different keys, once each is timer-triggered via `beginRun`, MUST be allowed to run concurrently with each other — each key gets its own independently created `Task` with no lock shared across keys; only same-key runs are serialized (per `one-run-per-key`), and only `flushAll()` additionally serializes *across* keys (see `flush-all-sequential-reports-still-failing` below).
- **success-retires-entry**: An entry MUST be removed from the debouncer once its work completes without throwing and its generation has not been superseded by a newer `schedule` call made while it ran.
- **failure-keeps-entry-and-rearms**: If `work` throws, the entry MUST NOT be removed; its `failures` count MUST be incremented and a retry timer MUST be armed for it — per the type's own doc comment, an entry leaves the debouncer only "on exactly two events: its work completed *without throwing*, or a caller explicitly `cancel`led it".
- **failure-callback-invoked-even-if-canceled**: `onFailure` (when supplied) MUST be called exactly once per failed attempt, with the failing `key` and the thrown error — and this call happens unconditionally, before `finishRun` checks whether an entry for that key still exists. Consequently, if `cancel(key:)` removes the entry while a run is in flight and that run's `work` closure subsequently throws (e.g. because it observed the cancellation), `onFailure` MUST still fire for a key the caller already cancelled; nothing in the source suppresses the callback for a since-removed entry.
- **superseded-run-resets-backoff**: When a run finishes for a generation older than the entry's current generation (i.e. newer work arrived while it ran), the entry's `failures` MUST be reset to zero and a fresh debounce-length timer MUST be armed, regardless of whether that superseded run succeeded or threw — whether the old attempt succeeded says nothing about the newer work.
- **retry-backoff-exponential-capped**: `retryInterval(afterFailures:)` MUST compute `debounce * 2^shift` where `shift = min(max(failures - 1, 0), 20)`, and MUST cap the result at `maximumRetryInterval` — backoff grows exponentially from the debounce window and never exceeds the configured ceiling, and the exponent's own cap of 20 MUST be applied independently of the `Duration` cap so the multiplication cannot overflow for a key that keeps failing indefinitely.
- **cancel-drops-entry-without-running**: `cancel(key:)` MUST remove `key`'s entry, MUST cancel its armed timer `Task` and any run `Task` in flight, and MUST NOT run the pending work — this is, together with success, the only way an entry leaves the debouncer.
- **cancel-during-run-not-resurrected**: If `cancel(key:)` runs while `key`'s work is in flight, the entry MUST already be absent by the time that run's `finishRun` executes, and `finishRun` MUST NOT recreate or re-arm it — `guard var entry = entries[key] else { return }` returns immediately for a key with no entry.
- **cancel-all-keys**: `cancelAll()` MUST apply the exact effect of `cancel(key:)`, individually, to every key present in the debouncer at the moment of the call.
- **cancellation-is-cooperative-only**: `cancel(key:)`'s `entry.run?.cancel()` MUST mark that run's `Task` as cancelled cooperatively; it MUST NOT forcibly interrupt a `work` closure that does not itself check `Task.isCancelled` or call a cancellable suspension point — such a closure MUST be allowed to run to completion even after `cancel(key:)` has already removed its entry.
- **flush-runs-now**: `flush(key:)` MUST run `key`'s pending work immediately, without waiting for its debounce window to elapse, and MUST NOT return until that attempt has completed.
- **flush-awaits-in-flight-run**: If a run for `key` is already executing when `flush(key:)` is called, `flush` MUST await that same run rather than starting a second one, including re-checking for a run started during its own suspension.
- **flush-all-sequential-reports-still-failing**: `flushAll()` MUST flush every currently pending key one at a time, in sequence — MUST NOT run two keys' flushes concurrently with each other — and MUST return the keys still present (i.e. still failing and re-armed) once every flush has been attempted.
- **pending-membership-reflects-any-state**: `pendingKeys` and `isPending(key:)` MUST report a key as pending for as long as any entry exists for it, whether it is waiting out its debounce window, currently running, or waiting to retry after a failure.
- **teardowns-mainactor-isolation**: `PendingTeardowns` MUST be declared `@MainActor` (`PendingTeardowns.swift`).
- **teardown-nonthrowing-closure**: `PendingTeardowns.Teardown` MUST be a non-throwing `@MainActor () async -> Void` closure type — per the doc comment, "a teardown that fails still happened, and there is no caller left to hand an error to"; a teardown that needs to report its own failure MUST do so itself (e.g. by logging), since `PendingTeardowns` provides no failure channel of any kind.
- **add-returns-immediately**: `add(_:)` MUST start `teardown` and MUST return without waiting for it to complete.
- **add-tracks-handle-per-token**: `add(_:)` MUST retain a `Task<Void, Never>` handle for every teardown it starts, each keyed by a freshly incremented token, for as long as that teardown is running.
- **entry-self-removes-on-completion**: The `Task` that `add(_:)` creates MUST remove its own tracked entry once its `teardown` closure completes, regardless of whether `drain()` is ever called — a teardown that finishes before anyone drains MUST NOT leave a stale handle behind.
- **drain-awaits-all-in-flight**: `drain()` MUST await every teardown currently tracked before it returns.
- **drain-awaits-teardowns-added-during-drain**: If a teardown being awaited by `drain()` itself calls `add(_:)` before finishing, `drain()` MUST also wait for that newly added teardown before returning — it MUST loop, taking a fresh snapshot of `tasks` each pass, until the tracked collection is observed empty, rather than making a single pass over the entries present when it was called.
- **drain-on-empty-returns-immediately**: `drain()` MUST return without suspending when no teardown is currently tracked (`while !tasks.isEmpty`).
- **in-flight-count-internal-visibility**: `inFlightCount` MUST report the exact number of teardowns currently tracked, and MUST be declared without `public` (internal access only) — the doc comment states its purpose is to let a test distinguish "started and tracked" from "started and dropped", not for use outside the module.

## Appearance

Not applicable — this is a set of three Foundation concurrency utilities, not a visual component.

## States

Not applicable — this is a set of three Foundation concurrency utilities, not a visual component. Their runtime states (a `KeyedDebouncer` entry's armed/running/retrying lifecycle) are captured under Behavioral Requirements above, not as a UI visual-state table.

## Accessibility

Not applicable — this is a set of three Foundation concurrency utilities, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| foundation-concurrency-001 | blocking-queue-hop, blocking-qos-default, blocking-sendable-boundary | `try await BlockingWork.run { Thread.isMainThread }`, called from the main actor, with no explicit `qos`. | Returns `false` — the closure ran on a GCD global queue thread, not the calling thread, and the default `.userInitiated` qos was accepted with no `qos:` argument. |
| foundation-concurrency-002 | blocking-throwing-resume | `try await BlockingWork.run { throw MyError.boom }`. | The `await` rethrows `MyError.boom` to the caller, unmodified. |
| foundation-concurrency-003 | blocking-throwing-resume | `try await BlockingWork.run { 42 }`. | Returns `42`. |
| foundation-concurrency-004 | blocking-nonthrowing-resume | `await BlockingWork.run { "done" }` (non-throwing closure, no `try`). | Returns `"done"`, compiles with no `try`/`throws` anywhere at the call site. |
| foundation-concurrency-005 | blocking-nonthrowing-resume | `WebviewSchemeHandler.contents(of:)` (`WebviewSchemeHandler.swift`): `await BlockingWork.run(qos: .userInitiated) { try? Data(contentsOf: file, options: .mappedIfSafe) }`. | Returns `Data?` — `nil` for a missing file, the file's bytes otherwise — with the read having happened off the calling actor; matches the non-throwing overload's contract of surfacing no error of its own. |
| foundation-concurrency-006 | blocking-throwing-resume, blocking-not-a-cancellation-point | `VSIXInstaller`'s use (`VSIXInstaller.swift`): `return try await BlockingWork.run { try VSIXArchive.verify(...) ... }`, with the enclosing `Task` cancelled immediately after the call starts. | The hash-and-signature verification inside the closure runs to completion regardless of the cancellation; the call either returns the installer's result or rethrows whatever `VSIXArchive.verify`/`install` threw — never a `CancellationError` injected by `BlockingWork` itself. |
| foundation-concurrency-007 | blocking-calls-run-independently | Issue ten concurrent `BlockingWork.run { Thread.current }` calls via `withTaskGroup`. | All ten complete without deadlock or blocking one another; `BlockingWork` itself performs no synchronization between the calls (none exists in `BlockingWork.swift`). |
| foundation-concurrency-008 | debouncer-mainactor-isolation, debounce-window-default, schedule-coalesces-latest | `KeyedDebouncerTests.tenSchedulesRunOnce`: schedule key `"a"` ten times, 3ms apart, with a 30ms debounce. | Only `"run-9"` (the last scheduled closure) is recorded; `isPending(key: "a") == false` after settling. |
| foundation-concurrency-009 | debouncer-key-constraint, cross-key-concurrency | `KeyedDebouncerTests.keysAreIndependent`: schedule distinct work for keys `"a"` and `"b"` at the same moment. | Both keys' work runs; `recorder.calls` contains both `"a"` and `"b"`; `pendingKeys.isEmpty` afterward. |
| foundation-concurrency-010 | cancel-drops-entry-without-running | `KeyedDebouncerTests.cancelDropsTheEntry`: schedule key `"a"`, then `cancel(key: "a")` before the debounce window elapses. | `recorder.calls.isEmpty`; `isPending(key: "a") == false`. |
| foundation-concurrency-011 | failure-keeps-entry-and-rearms, failure-callback-invoked-even-if-canceled | `KeyedDebouncerTests.failureStaysPending`: schedule key `"a"` whose work always throws; supply an `onFailure` collecting `(key, error)` pairs. | Every recorded call is the failing attempt (`"!a"`); `failures` (the `onFailure` log) is non-empty and every entry names `"a"`; `isPending(key: "a") == true` after settling. |
| foundation-concurrency-012 | success-retires-entry, retry-backoff-exponential-capped | `KeyedDebouncerTests.failedEntrySurvivesToALaterFlush`: after `"a"` has failed and is pending, stop it from throwing, then `await debouncer.flush(key: "a")`. | `recorder.successes(for: "a") == 1`; `isPending(key: "a") == false` — the retained entry finally succeeds and retires. |
| foundation-concurrency-013 | flush-all-sequential-reports-still-failing | `KeyedDebouncerTests.flushAllReportsSurvivingFailures`: schedule `"good"` (succeeds) and `"bad"` (always throws) with a 60-second debounce, then `await debouncer.flushAll()`. | Returns `["bad"]`; `recorder.successes(for: "good") == 1`. |
| foundation-concurrency-014 | retry-backoff-exponential-capped | `KeyedDebouncerTests.retryBackoffIsCapped`: `debounce: 10ms`, `maximumRetryInterval: 20ms`, key `"a"` always throws; wait 300ms. | `recorder.calls.count >= 3` — several retries fired within the window, consistent with an exponential backoff capped at 20ms rather than growing unbounded; `isPending(key: "a") == true`. |
| foundation-concurrency-015 | one-run-per-key, flush-awaits-in-flight-run | `KeyedDebouncerTests.flushAwaitsTheRunInFlight`: schedule work for `"a"` that blocks on a gate; once it has entered, call `flush(key: "a")` concurrently, then open the gate. | While the first run is in flight, `gate.entries` stays `1` even after `flush` is invoked (no second run starts); after the gate opens and `flush` completes, `gate.entries == 1` still and `isPending(key: "a") == false`. |
| foundation-concurrency-016 | schedule-during-run-defers-timer, superseded-run-resets-backoff | `KeyedDebouncerTests.newerWorkDuringARunIsNotLost`: while `"a"`'s first run is blocked on a gate, call `schedule(key: "a")` again with different work, then open the gate. | Both closures run, in order (`ran == ["first", "second"]`); the entry is not lost despite the reschedule happening mid-run; `isPending(key: "a") == false` once the second run also finishes. |
| foundation-concurrency-017 | cancel-during-run-not-resurrected, cancellation-is-cooperative-only | `KeyedDebouncerTests.cancelDuringARunWins`: while `"a"`'s run is blocked on a gate (which ignores cancellation via `try?`), call `cancel(key: "a")`, then open the gate. | `isPending(key: "a") == false` after the run eventually finishes — cancelling did not stop the gate-waiting closure (it ran to completion once opened), and its completion did not resurrect the already-cancelled entry. |
| foundation-concurrency-018 | retry-ceiling-default-and-floor | `KeyedDebouncer<String>(debounce: .seconds(5), maximumRetryInterval: .seconds(1))`. | Constructs without error; the effective ceiling used by `retryInterval(afterFailures:)` is `.seconds(5)` (raised to match `debounce`), never the smaller `.seconds(1)` passed in. |
| foundation-concurrency-019 | teardowns-mainactor-isolation, add-returns-immediately, drain-awaits-all-in-flight | `PendingTeardownsTests.drainWaitsForWorkInFlight`: `add` a teardown that sleeps 150ms before recording `"slow"`. | Immediately after `add`, nothing is recorded; after `await teardowns.drain()` returns, `journal.finished == ["slow"]`. |
| foundation-concurrency-020 | drain-awaits-all-in-flight | `PendingTeardownsTests.drainWaitsForAllOfThem`: `add` five teardowns with staggered delays. | `await teardowns.drain()` returns only once all five have recorded — `journal.finished.count == 5`. |
| foundation-concurrency-021 | drain-awaits-teardowns-added-during-drain | `PendingTeardownsTests.drainWaitsForTeardownsStartedByTeardowns`: an added teardown records `"outer"` and then itself `add`s a second teardown recording `"inner"`. | `await teardowns.drain()` returns only after both have recorded, in order — `journal.finished == ["outer", "inner"]`. |
| foundation-concurrency-022 | entry-self-removes-on-completion, in-flight-count-internal-visibility | `PendingTeardownsTests.finishedTeardownsAreForgotten`: `add {}`, drain, then `add {}` again without draining and wait past its completion. | `inFlightCount == 0` after the drained case; `inFlightCount == 0` again after the un-drained instant teardown has had time to finish on its own. |
| foundation-concurrency-023 | drain-on-empty-returns-immediately | `PendingTeardownsTests.drainOnEmptyReturns`: call `await teardowns.drain()` on a freshly constructed `PendingTeardowns` with nothing added. | Returns promptly with no suspension; `inFlightCount == 0`. |
| foundation-concurrency-024 | teardown-nonthrowing-closure | Attempt to write `teardowns.add { try someThrowingCall() }` with the throwing call left unhandled. | Fails to compile — `Teardown` is `@MainActor () async -> Void`, not `throws`, so an unhandled `try` inside the closure is a compile error; the caller must use `try?`/`try!` or its own `do`/`catch`. |
| foundation-concurrency-025 | cancel-all-keys | Schedule work for keys `"a"`, `"b"`, and `"c"` on one debouncer, then call `cancelAll()`. | `pendingKeys.isEmpty == true` and none of the three closures ran. |

## Edge Cases

- **Null / empty input**: `PendingTeardowns.add {}` (a no-op teardown) MUST be tracked and drained exactly like any other teardown, per `PendingTeardownsTests.finishedTeardownsAreForgotten`. `KeyedDebouncer.schedule(key:_:)` imposes no validation on `Key` — an empty `String` key or any other "empty" `Hashable` value MUST be accepted and treated like any other key, since the type performs no content inspection of `Key`, only hashing and equality. `BlockingWork.run` imposes no validation on its closure or `T` — a closure that returns immediately with a trivially empty value (`Void`, `""`, `Data()`) MUST be handled identically to any other closure.
- **Boundary values**: A `debounce` or `maximumRetryInterval` of `.zero` MUST be accepted by `KeyedDebouncer.init` — no lower bound is enforced beyond the `max(debounce, maximumRetryInterval)` floor already stated in `retry-ceiling-default-and-floor`; a `.zero` debounce degenerates to running on (approximately) the next main-actor turn rather than truly debouncing. The retry-backoff exponent shift is explicitly capped at 20 (`retry-backoff-exponential-capped`) specifically so an entry that keeps failing for an extremely long time cannot overflow the `1 << shift` computation — this is a MUST, not incidental. `PendingTeardowns.nextToken` is a plain `Int` that increments once per `add(_:)` call with no wraparound handling; the source contains no upper-bound check on it.
- **Concurrent access**: `KeyedDebouncer` and `PendingTeardowns` MUST serialize every call to their own public API through `@MainActor` isolation (per `debouncer-mainactor-isolation` and `teardowns-mainactor-isolation`) — two `Task`s calling `schedule`/`cancel`/`add`/`drain` "concurrently" are actually serialized onto the main actor, one at a time, with only their `await` points as interleaving opportunities. `BlockingWork` holds no shared mutable state at all, so concurrent calls to `run` from any number of tasks MUST be safe with no synchronization, per `blocking-calls-run-independently`.
- **Error states**: A `KeyedDebouncer` work closure that throws MUST leave its entry pending and re-armed rather than lost, per `failure-keeps-entry-and-rearms` — this is the specific bug (a full disk, a revoked network volume silently dropping the pending save) the type's own doc comment says it was extracted to fix. `PendingTeardowns.Teardown` is non-throwing by design (`teardown-nonthrowing-closure`); a teardown that encounters an internal error and wants that visible MUST catch and report it itself (e.g. by logging) before returning, since nothing in `PendingTeardowns` observes or surfaces it. `BlockingWork.run`'s throwing overload MUST propagate `work`'s thrown error to the caller unchanged, per `blocking-throwing-resume`; its non-throwing overload has no error path at all, by the caller's choice of overload.
- **Offline / disconnected state**: Not applicable — none of the three types performs network access itself; each only decides where (`BlockingWork`) or when (`KeyedDebouncer`, `PendingTeardowns`) a caller-supplied closure runs. A closure whose own work involves a network call (none of the current call sites' closures do; they are file I/O, archive verification, or main-actor state teardown) would surface connectivity loss as a thrown error through the same paths already described under Error States, not through any offline-specific behavior these three files define.
- **Cancellation**: `BlockingWork.run` MUST ignore cancellation of the calling task once `work` is dispatched (`blocking-not-a-cancellation-point`) — a cancelled caller still waits for the full synchronous closure to return. `KeyedDebouncer.cancel(key:)` cancels the entry's timer and run `Task`s cooperatively only; a `work` closure that never checks `Task.isCancelled` and never calls a cancellable suspension point MUST be allowed to keep running to completion after `cancel(key:)` has already discarded its entry, per `cancellation-is-cooperative-only` — `KeyedDebouncerTests.cancelDuringARunWins` exercises exactly this shape with a gate closure that swallows cancellation via `try?`. `PendingTeardowns` exposes no cancellation entry point at all; `drain()` only awaits tracked teardowns, it never cancels one.
- **Owner deallocation while work is pending**: `KeyedDebouncer.armTimer`'s and `beginRun`'s `Task`s each capture `[weak self]`; if the last strong reference to a `KeyedDebouncer` instance is released while a timer is armed or a run is executing, the closure's `guard ... let self else { return }` MUST cause that step to no-op — the `entries` dictionary and its stored `work` closures are deallocated along with `self`, and neither the pending work nor an `onFailure` call ever happens. This is a SHOULD-level caller obligation, not a marker: a caller that needs every scheduled write to complete SHOULD call `flushAll()` before releasing its `KeyedDebouncer`, exactly as `PendingTeardowns.drain()` exists to guarantee for detached teardown work at the call sites that motivated it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `qos` (parameter to `BlockingWork.run`) | `DispatchQoS.QoSClass` | `.userInitiated` | The GCD global queue's quality-of-service class the closure is dispatched to. |
| `work` (parameter to `BlockingWork.run`) | `@Sendable () throws -> T` or `@Sendable () -> T` | none — required | The synchronous, thread-blocking closure to run off the cooperative pool. |
| `debounce` (parameter to `KeyedDebouncer.init`) | `Duration` | `.seconds(1)` | How long a key stays quiet before its scheduled work runs. |
| `maximumRetryInterval` (parameter to `KeyedDebouncer.init`) | `Duration` | `.seconds(30)`, floored at `debounce` | Ceiling on the exponential backoff applied after a failed attempt. |
| `onFailure` (parameter to `KeyedDebouncer.init`) | `(@MainActor (Key, any Error) -> Void)?` | `nil` | Called once per failed attempt with the key and the error; the debouncer itself never logs. |
| `work` (parameter to `KeyedDebouncer.schedule(key:_:)`) | `Work` (`@MainActor () async throws -> Void`) | none — required, per key | The work to (re-)schedule for `key`, replacing whatever was previously scheduled for it. |
| `teardown` (parameter to `PendingTeardowns.add`) | `Teardown` (`@MainActor () async -> Void`) | none — required | The fire-and-forget teardown to start and track. |

None of the three files reads an environment variable or a settings key; every value they operate on arrives as an initializer or method parameter.

## Deep Linking

Not applicable: none of `BlockingWork.swift`, `KeyedDebouncer.swift`, or `PendingTeardowns.swift` defines a URL scheme, route, or navigation destination — they schedule and dispatch closures, not app navigation.

## Localization

Not applicable: none of the three files contains a user-facing string literal — each operates on a generic `T`/`Key`/opaque closure supplied by its caller, with no string of its own to localize.

## Accessibility Options

Not applicable: none of the three files presents UI, so none responds to Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of the three files contains a feature-flag or settings-key reference of its own.

## Analytics

Not applicable: none of the three files contains an analytics or event-tracking call.

## Privacy

- **Data handled**: None of the three types defines a data field of its own — each only carries whatever the caller's closure captures or returns. In practice that closure MAY handle sensitive data: `VSIXInstaller`'s use of `BlockingWork.run` verifies a signature and digest inside the closure (`VSIXInstaller.swift`), and `OpenDocumentReloader`'s use reads arbitrary file contents (`OpenDocumentReloader.swift`) that MAY be sensitive user documents. None of `BlockingWork.swift`, `KeyedDebouncer.swift`, or `PendingTeardowns.swift` itself inspects, parses, or branches on the content of any value passing through it.
- **Storage**: None of the three files persists anything; each holds a closure or a `Task` handle only in memory for the duration of one dispatched call, one debounce cycle, or one teardown's execution.
- **Transmission**: None of the three files transmits data itself; whatever a wrapped closure does with the network (none of the current call sites' closures perform network I/O) is entirely outside these files.
- **Retention**: None — `BlockingWork` retains nothing past one `run` call; a `KeyedDebouncer` entry is retained only until it succeeds or is cancelled (with failed entries retained specifically so `flushAll()` can find them at shutdown, per the type's own doc comment); a `PendingTeardowns` task handle is retained only until its teardown completes.

## Logging

Not applicable: none of `BlockingWork.swift`, `KeyedDebouncer.swift`, or `PendingTeardowns.swift` calls `os_log`, `Logger`, `print`, or any other logging API. `KeyedDebouncer`'s doc comment states this explicitly for itself — "the debouncer itself never logs; whoever owns the work owns how a failure is reported" — and reports a failure only through the caller-supplied `onFailure` closure, which MAY log but is not required to.

## Platform Notes

- **SwiftUI**: The sources are `packages/apple/AgenticToolkit/Core/Concurrency/BlockingWork.swift`, `KeyedDebouncer.swift`, and `PendingTeardowns.swift`, part of the `AgenticToolkitCore` framework target, which `project.yml` declares as `platform: macOS` only (no iOS target exists for it today). Nothing in any of the three files is SwiftUI-specific — each imports only `Foundation` — so a SwiftUI or AppKit host consumes them identically; `KeyedDebouncer` and `PendingTeardowns` are consumed today from `@MainActor`-isolated AppKit controllers (`NotesManager`, `ProjectWindowManager`) rather than SwiftUI views.
- **Compose**: There is no direct Kotlin equivalent to `BlockingWork` because Kotlin coroutines' default dispatchers already separate blocking work by convention — port a blocking call with `withContext(Dispatchers.IO) { ... }` rather than a bespoke type, since `Dispatchers.IO`'s elastic thread pool is the same "pool that is allowed to block" role GCD's global queue plays here. Port `KeyedDebouncer<Key>` as a class holding a `MutableStateFlow`-free `Map<Key, Entry>` guarded by confinement to a single-threaded `CoroutineDispatcher` (the direct analogue of `@MainActor`), with each `Entry` holding a `Job?` for its timer and a `Job?` for its run, `launch { delay(debounceMs) }` in place of `Task { try await Task.sleep(for:) }`, and the same generation-bump/backoff bookkeeping. Port `PendingTeardowns` as a class tracking a `MutableMap<Int, Job>` on that same confined dispatcher, with `drain()` looping `while (tasks.isNotEmpty()) { ...; job.joinAll() }`.
- **React/Web**: There is no blocking-thread problem to solve in JavaScript's single-threaded event loop, so `BlockingWork` has no web port at all — any port of the sibling two types should simply run their work on the one thread the platform provides. Port `KeyedDebouncer<Key>` as a `Map<Key, { timer: ReturnType<typeof setTimeout> | null, running: Promise<void> | null, generation: number, failures: number }>`, using `setTimeout`/`clearTimeout` in place of the `Task`-based timer and `setTimeout` with `2 ** shift` multiplication (capped) for the retry backoff. Port `PendingTeardowns` as a `Map<number, Promise<void>>` plus a `drain()` that loops `while (tasks.size > 0) { const inFlight = [...tasks.values()]; tasks.clear(); await Promise.all(inFlight); }`, mirroring the source's re-snapshot-then-await loop exactly.
- **AppKit / UIKit**: Identical to the SwiftUI note — all three files are UI-framework-agnostic; only the application embedding `AgenticToolkitCore` differs, never this contract. `PendingTeardowns`' own doc comment cites a UIKit-adjacent motivating case directly analogous to AppKit's `ProjectWindowManager`: a window-close notification handler that must not block the UI on an async teardown.
- **WinUI 3**: There is no `Task.detached`-vs-cooperative-pool distinction in .NET the way there is in Swift concurrency — `Task.Run` already dispatches to the thread pool, and the thread pool itself grows when its worker threads block, which is the behavior `BlockingWork` exists to get from GCD specifically because Swift's pool refuses to have it. Port `BlockingWork.run` as a thin wrapper over `Task.Run(() => work())` (or `await Task.Run(work).ConfigureAwait(false)` at call sites) rather than porting its internal continuation plumbing — the GCD hop has no WinUI 3 counterpart to build because .NET's default thread pool already is one. Port `KeyedDebouncer<TKey>` as a class confined to a single `SynchronizationContext` (WinUI 3's UI-thread analogue to `@MainActor`) holding `Dictionary<TKey, Entry>`, where `Entry` carries a `CancellationTokenSource?` for its timer (`Task.Delay(delay, cts.Token)` in place of `Task.sleep(for:)`) and a `Task?` for its run, with the same generation-bump-on-reschedule and `Math.Min(debounce * (1 << shift), maximumRetryInterval)` backoff math; `KeyedDebouncer`'s `onFailure` maps to a `Action<TKey, Exception>?` callback parameter. Port `PendingTeardowns` as a class tracking `Dictionary<int, Task>` on that same `SynchronizationContext`, with `DrainAsync()` looping `while (tasks.Count > 0) { var inFlight = tasks.Values.ToList(); tasks.Clear(); await Task.WhenAll(inFlight); }` — the same re-snapshot-then-await-all loop, since a WinUI 3 window's `Closing` handler is exactly the "must not block the UI on a subprocess exiting" case `PendingTeardowns`' doc comment describes for its AppKit caller.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Concurrency/` |

## Design Decisions

**Decision**: `KeyedDebouncer.finishRun` calls `onFailure?(key, error)` unconditionally, before it checks whether an entry for that key still exists.
**Rationale**: This means a caller who calls `cancel(key:)` while that key's work is in flight, and whose `work` closure subsequently throws (for instance because it observed the cancellation and threw), MUST still receive an `onFailure` callback naming a key that caller already explicitly cancelled — see `failure-callback-invoked-even-if-canceled` above. The code makes no attempt to suppress this: `finishRun`'s existence guard runs strictly after the `onFailure` call. Reporting every thrown error unconditionally is evidently favored over consistency with the cancelled state, since the alternative — checking entry existence first — would require reordering two lines that currently have no comment explaining the choice either way.
**Approved**: pending

**Decision**: `KeyedDebouncer` reports failures through an optional `onFailure` callback, while `PendingTeardowns.Teardown` provides no failure channel at all.
**Rationale**: The two types serve different obligations. `KeyedDebouncer` exists specifically to make a failed write retryable and eventually reportable — its own doc comment describes the exact bug (a full disk silently dropping a save) it was extracted to fix, so a failure that could recur MUST be observable to something that decides whether to keep retrying or surface it to a user. `PendingTeardowns` exists only to guarantee a teardown is *waited for*, not to give it a durable retry lifecycle; its doc comment states plainly that "there is no caller left to hand an error to" once the entry that started the teardown is gone. A `Teardown` that wants failure visibility must log it itself before returning.
**Approved**: pending

**Decision**: `flushAll()` runs every pending key's flush sequentially, one after another, even though `KeyedDebouncer` otherwise allows different keys' timer-triggered runs to execute fully concurrently with each other.
**Rationale**: Per the doc comment on `flushAll`, "the copies this replaces were sequential and their work writes to a shared destination; nothing here needs the parallelism, and serialising keeps a failure attributable." This is a deliberate asymmetry specific to the one call path (`flushAll`) that iterates every key at once, not a change to the general concurrency model described in `cross-key-concurrency` above.
**Approved**: pending

**Decision**: `BlockingWork.run` imposes no timeout, deadline, or cancellation of its own on the closure it dispatches.
**Rationale**: Per the type's doc comment, "this type only decides *where* it runs" — bounding how long the work may take is left entirely to the closure itself, the way `VSIXInstaller`'s `CommandRunner` already enforces its own 124-second budget (a timeout plus two termination graces) independently of `BlockingWork`. Centralizing a timeout in the shared hop would apply one policy to every disparate blocking operation (an archive extraction, a whole-file read, a directory scan) that currently each own their own bound, or none at all where none is needed.
**Approved**: pending

**Decision**: `KeyedDebouncer.armTimer`/`beginRun` capture `[weak self]`, so a `KeyedDebouncer` instance that is deallocated while work is armed or running silently drops that work with no signal to anyone.
**Rationale**: This is the caller's own lifecycle responsibility, not a defect in the type — `PendingTeardowns` exists precisely to solve the analogous problem (detached work outliving the object that started it) for the call sites that need that guarantee, and a caller of `KeyedDebouncer` that needs every scheduled write to complete before its debouncer goes away SHOULD call `flushAll()` first, exactly as a quit path calls `PendingTeardowns.drain()`. See the "Owner deallocation while work is pending" edge case above.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |

Notes: `separation-of-concerns` passes because each of the three types addresses exactly one concern with no overlap — `BlockingWork` only decides *where* a closure runs, `KeyedDebouncer` only decides *when* per-key work runs and how a failed attempt is retried, and `PendingTeardowns` only tracks unawaited work so a shutdown path can wait for it — none reaches into the others' responsibility. `unit-test-coverage` is partial because `KeyedDebouncerTests.swift` and `PendingTeardownsTests.swift` each exercise their type directly with meaningful assertions, but `BlockingWork.swift` has no dedicated test file of its own anywhere in the repository; it is exercised only indirectly, through `OpenDocumentReloaderTests.swift`'s comments about which GCD thread a caller's closure lands on. `explicit-error-handling` passes because every failure path is explicit and traced above: `BlockingWork`'s throwing overload rethrows faithfully, and `KeyedDebouncer` never drops a thrown error — it keeps the entry pending, reports it through `onFailure`, and retries with backoff, which is the specific silent-swallowing bug (per its own doc comment) the type replaces three prior hand-copies to fix. `fault-tolerance` passes because all three types handle any input their contracts admit — any `Hashable & Sendable` key, any closure, an empty collection of pending entries or teardowns — without crashing; a throwing `work` closure is caught, not left to propagate as a crash. `idempotent-operations` is partial because `KeyedDebouncer` guarantees the *retry mechanism* is safe (never two overlapping attempts for the same key, and a superseded attempt's outcome is discarded rather than double-applied), but it imposes no idempotency on the wrapped `work` closure itself — whether a given write is safe to repeat is entirely the caller's responsibility, not something either type can verify. `main-thread-freedom` passes because keeping blocking, thread-occupying work off the actor-isolated cooperative pool is the entire purpose of `BlockingWork`, and both `KeyedDebouncer` and `PendingTeardowns` are `@MainActor`-isolated for their own bookkeeping only, with their `async` work closures explicitly free to (and, per their doc comments, expected to) leave the main actor for anything that touches a disk.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
