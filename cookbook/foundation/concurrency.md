---
id: 4e06a00e-653a-4d29-81d8-ac6dccfedb6a
title: Concurrency
domain: agentictoolkit://cookbook/foundation/concurrency
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An off-pool blocking hop, a per-key debounce-with-retry scheduler, and
  a drainable teardown tracker.
platforms:
- swift
- macos
tags:
- concurrency
- foundation
- debounce
- retry
- teardown
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/registry/extension-registry
- agentictoolkit://cookbook/workspace/extensions/registry/vsix-installer
references: []
approved-by: ''
approved-date: ''
---

# Concurrency

## Overview

Three Foundation-only utilities that each solve one recurring structured-concurrency mistake found independently at two or more call sites in this codebase. A blocking-work helper (a stateless namespace) hops a synchronous, thread-blocking closure onto a background dispatch queue and resumes the calling operation with its result, so that work sitting on a semaphore or a large synchronous file read never occupies one of the cooperative thread pool's core-count threads. A keyed debouncer coalesces repeated per-key work into one debounced run and guarantees that a run which fails is never dropped: the entry stays pending and re-arms with exponential backoff until it succeeds or is explicitly cancelled. A pending-teardowns tracker holds a handle for teardown work started without a waiter, so a later shutdown path can drain and be certain nothing it started is still in flight. None of the three performs any I/O of its own; each only manages *where* or *when* a caller-supplied closure runs.

## Behavioral Requirements

- **blocking-queue-hop**: `run` (both overloads) MUST execute `work` on a background dispatch queue, never on the cooperative thread pool that ordinary concurrent work shares.
- **blocking-qos-default**: Both `run` overloads MUST default their `qos` parameter to `userInitiated` when the caller omits it.
- **blocking-throwing-resume**: The throwing overload MUST resume the caller with whatever value `work` returned, or propagate whatever error `work` raised, unchanged.
- **blocking-nonthrowing-resume**: The non-throwing overload MUST resume the caller with exactly the value `work` returned, with no error path.
- **blocking-concurrency-boundary**: On both overloads, the result value and the `work` closure itself MUST both be safe to pass across a thread boundary, because the value crosses one once into the closure's execution context and once back out through the resumption.
- **blocking-not-a-cancellation-point**: `run` MUST NOT observe or react to cancellation of the calling operation once `work` has been dispatched — the caller resumes only when the synchronous `work` closure itself returns or fails; a caller needing bounded execution MUST give `work` its own deadline, the way the command-runner utility does.
- **blocking-calls-run-independently**: Two or more concurrent calls to `run` MUST run independently of one another with no shared state and no coordination between them — the blocking-work helper holds no instance or shared mutable state, so any number of calls MAY execute in parallel, each on whatever thread the background queue grows to serve it.
- **debouncer-confined-isolation**: The keyed debouncer MUST confine itself to a single serial execution context, so every one of its operations (`schedule`, `cancel`, `cancelAll`, `flush`, `flushAll`, `pendingKeys`, `isPending`) MUST run on, and only be callable from, that same context.
- **debouncer-key-constraint**: The debouncer's key type MUST be hashable and safe to pass across concurrent contexts.
- **debounce-window-default**: Construction MUST default `debounce` to 1 second when the caller omits it.
- **retry-ceiling-default-and-floor**: Construction MUST default `maximumRetryInterval` to 30 seconds and MUST clamp the stored ceiling to be at least `debounce` — a caller passing a `maximumRetryInterval` smaller than `debounce` MUST NOT be rejected; the smaller value is silently raised to `debounce` instead.
- **schedule-coalesces-latest**: `schedule` MUST replace whatever work was previously scheduled for `key` with the new closure and MUST restart the debounce window from the moment of the call — only the most recently scheduled closure for a key is ever run, never a queue of every call.
- **schedule-during-run-defers-timer**: Calling `schedule` while `key`'s work is already running MUST NOT cancel that run and MUST NOT start a second run for the same key; it MUST record the newer work by bumping the entry's generation counter and resetting its failure count to zero, and MUST cancel any armed timer without re-arming it until the running work finishes.
- **one-run-per-key**: The debouncer MUST NOT run more than one instance of a given key's work concurrently — starting a run MUST have no effect when that key already has a run in progress.
- **cross-key-concurrency**: Work for two different keys, once each is timer-triggered, MUST be allowed to run concurrently with each other — each key's run proceeds independently with no lock shared across keys; only same-key runs are serialized (per `one-run-per-key`), and only `flushAll` additionally serializes *across* keys (see `flush-all-sequential-reports-still-failing` below).
- **success-retires-entry**: An entry MUST be removed from the debouncer once its work completes without failing and its generation has not been superseded by a newer `schedule` call made while it ran.
- **failure-keeps-entry-and-rearms**: If `work` fails, the entry MUST NOT be removed; its failure count MUST be incremented and a retry timer MUST be armed for it — an entry leaves the debouncer only on exactly two events: its work completed without failing, or a caller explicitly cancelled it.
- **failure-callback-invoked-even-if-canceled**: `onFailure` (when supplied) MUST be called exactly once per failed attempt, with the failing `key` and the error — and this call happens unconditionally, before the debouncer checks whether an entry for that key still exists. Consequently, if `cancel` removes the entry while a run is in flight and that run's `work` closure subsequently fails (e.g. because it observed the cancellation), `onFailure` MUST still fire for a key the caller already cancelled; nothing suppresses the callback for a since-removed entry.
- **superseded-run-resets-backoff**: When a run finishes for a generation older than the entry's current generation (i.e. newer work arrived while it ran), the entry's failure count MUST be reset to zero and a fresh debounce-length timer MUST be armed, regardless of whether that superseded run succeeded or failed — whether the old attempt succeeded says nothing about the newer work.
- **retry-backoff-exponential-capped**: `retryInterval` MUST compute `debounce * 2^shift` where `shift = min(max(failures - 1, 0), 20)`, and MUST cap the result at `maximumRetryInterval` — backoff grows exponentially from the debounce window and never exceeds the configured ceiling, and the exponent's own cap of 20 MUST be applied independently of the ceiling cap so the multiplication cannot overflow for a key that keeps failing indefinitely.
- **cancel-drops-entry-without-running**: `cancel` MUST remove `key`'s entry, MUST cancel its armed timer and any run in flight, and MUST NOT run the pending work — this is, together with success, the only way an entry leaves the debouncer.
- **cancel-during-run-not-resurrected**: If `cancel` runs while `key`'s work is in flight, the entry MUST already be absent by the time that run finishes, and finishing MUST NOT recreate or re-arm it — an already-cancelled key with no entry MUST leave the finishing run's cleanup with nothing to do.
- **cancel-all-keys**: `cancelAll` MUST apply the exact effect of `cancel`, individually, to every key present in the debouncer at the moment of the call.
- **cancellation-is-cooperative-only**: `cancel`'s cancellation of a run MUST mark that run as cancelled cooperatively; it MUST NOT forcibly interrupt a `work` closure that does not itself check for cancellation or reach a cancellable suspension point — such a closure MUST be allowed to run to completion even after `cancel` has already removed its entry.
- **flush-runs-now**: `flush` MUST run `key`'s pending work immediately, without waiting for its debounce window to elapse, and MUST NOT return until that attempt has completed.
- **flush-awaits-in-flight-run**: If a run for `key` is already executing when `flush` is called, `flush` MUST await that same run rather than starting a second one, including re-checking for a run started during its own suspension.
- **flush-all-sequential-reports-still-failing**: `flushAll` MUST flush every currently pending key one at a time, in sequence — MUST NOT run two keys' flushes concurrently with each other — and MUST return the keys still present (i.e. still failing and re-armed) once every flush has been attempted.
- **pending-membership-reflects-any-state**: `pendingKeys` and `isPending` MUST report a key as pending for as long as any entry exists for it, whether it is waiting out its debounce window, currently running, or waiting to retry after a failure.
- **teardowns-confined-isolation**: The pending-teardowns tracker MUST confine itself to a single serial execution context.
- **teardown-nonthrowing-closure**: A teardown MUST be a closure that cannot fail — a teardown that fails still happened, and there is no caller left to hand an error to; a teardown that needs to report its own failure MUST do so itself (e.g. by logging), since the tracker provides no failure channel of any kind.
- **add-returns-immediately**: Adding a teardown MUST start it and MUST return without waiting for it to complete.
- **add-tracks-handle-per-token**: Adding a teardown MUST retain a handle for every teardown it starts, each keyed by a freshly incremented token, for as long as that teardown is running.
- **entry-self-removes-on-completion**: The tracked entry for an added teardown MUST remove itself once that teardown completes, regardless of whether `drain` is ever called — a teardown that finishes before anyone drains MUST NOT leave a stale handle behind.
- **drain-awaits-all-in-flight**: `drain` MUST await every teardown currently tracked before it returns.
- **drain-awaits-teardowns-added-during-drain**: If a teardown being awaited by `drain` itself adds another teardown before finishing, `drain` MUST also wait for that newly added teardown before returning — it MUST loop, taking a fresh snapshot of the tracked entries each pass, until none remain, rather than making a single pass over the entries present when it was called.
- **drain-on-empty-returns-immediately**: `drain` MUST return without suspending when no teardown is currently tracked.
- **in-flight-count-internal-visibility**: `inFlightCount` MUST report the exact number of teardowns currently tracked, and MUST be visible only within the module, not published externally — its purpose is to let a test distinguish "started and tracked" from "started and dropped", not for use outside the module.

## Appearance

Not applicable — this is a set of three Foundation concurrency utilities, not a visual component.

## States

Not applicable — this is a set of three Foundation concurrency utilities, not a visual component. Their runtime states (a debouncer entry's armed/running/retrying lifecycle) are captured under Behavioral Requirements above, not as a UI visual-state table.

## Accessibility

Not applicable — this is a set of three Foundation concurrency utilities, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| foundation-concurrency-001 | blocking-queue-hop, blocking-qos-default, blocking-concurrency-boundary | Call `run` with a closure that checks whether the calling thread is the main thread, called from the main execution context, with no explicit `qos`. | Returns `false` — the closure ran on a background queue thread, not the calling thread, and the default `userInitiated` qos was accepted with no `qos` argument. |
| foundation-concurrency-002 | blocking-throwing-resume | Call `run` with a closure that immediately fails with a custom error. | The call propagates that error to the caller, unmodified. |
| foundation-concurrency-003 | blocking-throwing-resume | Call `run` with a closure returning `42`. | Returns `42`. |
| foundation-concurrency-004 | blocking-nonthrowing-resume | Call the non-throwing overload of `run` with a closure returning `"done"`. | Returns `"done"`, with no failure-handling required at the call site. |
| foundation-concurrency-005 | blocking-nonthrowing-resume | A host's file-content reader calls `run` with `qos: userInitiated` and a closure that reads a file's bytes, tolerating a missing file. | Returns the file's bytes, or nothing for a missing file, with the read having happened off the calling context; matches the non-throwing overload's contract of surfacing no error of its own. |
| foundation-concurrency-006 | blocking-throwing-resume, blocking-not-a-cancellation-point | A plugin installer calls the throwing overload of `run` to verify an archive's hash and signature, with the enclosing operation cancelled immediately after the call starts. | The verification inside the closure runs to completion regardless of the cancellation; the call either returns the installer's result or propagates whatever error the verification raised — never a cancellation error injected by the helper itself. |
| foundation-concurrency-007 | blocking-calls-run-independently | Issue ten concurrent calls to `run`, each reading the current thread. | All ten complete without deadlock or blocking one another; the helper itself performs no synchronization between the calls. |
| foundation-concurrency-008 | debouncer-confined-isolation, debounce-window-default, schedule-coalesces-latest | Schedule key `"a"` ten times, 3ms apart, with a 30ms debounce. | Only the last scheduled closure (`"run-9"`) is recorded; the key is no longer pending after settling. |
| foundation-concurrency-009 | debouncer-key-constraint, cross-key-concurrency | Schedule distinct work for keys `"a"` and `"b"` at the same moment. | Both keys' work runs; the recorded calls include both `"a"` and `"b"`; no key remains pending afterward. |
| foundation-concurrency-010 | cancel-drops-entry-without-running | Schedule key `"a"`, then cancel it before the debounce window elapses. | No call is recorded; the key is not pending. |
| foundation-concurrency-011 | failure-keeps-entry-and-rearms, failure-callback-invoked-even-if-canceled | Schedule key `"a"` whose work always fails; supply an `onFailure` callback collecting `(key, error)` pairs. | Every recorded call is the failing attempt (`"!a"`); the failure log is non-empty and every entry names `"a"`; the key remains pending after settling. |
| foundation-concurrency-012 | success-retires-entry, retry-backoff-exponential-capped | After `"a"` has failed and is pending, stop it from failing, then flush key `"a"`. | Exactly one success is recorded for `"a"`; the key is no longer pending — the retained entry finally succeeds and retires. |
| foundation-concurrency-013 | flush-all-sequential-reports-still-failing | Schedule `"good"` (succeeds) and `"bad"` (always fails) with a 60-second debounce, then flush all. | Returns `["bad"]`; exactly one success is recorded for `"good"`. |
| foundation-concurrency-014 | retry-backoff-exponential-capped | With a 10ms debounce and a 20ms retry ceiling, key `"a"` always fails; wait 300ms. | At least 3 calls are recorded — several retries fired within the window, consistent with an exponential backoff capped at 20ms rather than growing unbounded; the key remains pending. |
| foundation-concurrency-015 | one-run-per-key, flush-awaits-in-flight-run | Schedule work for `"a"` that blocks on a gate; once it has entered, flush key `"a"` concurrently, then open the gate. | While the first run is in flight, the gate's entry count stays at `1` even after flush is invoked (no second run starts); after the gate opens and flush completes, the entry count is still `1` and the key is no longer pending. |
| foundation-concurrency-016 | schedule-during-run-defers-timer, superseded-run-resets-backoff | While `"a"`'s first run is blocked on a gate, schedule `"a"` again with different work, then open the gate. | Both closures run, in order (`"first"`, then `"second"`); the entry is not lost despite the reschedule happening mid-run; the key is no longer pending once the second run also finishes. |
| foundation-concurrency-017 | cancel-during-run-not-resurrected, cancellation-is-cooperative-only | While `"a"`'s run is blocked on a gate that ignores cancellation, cancel key `"a"`, then open the gate. | The key is no longer pending after the run eventually finishes — cancelling did not stop the gate-waiting closure (it ran to completion once opened), and its completion did not resurrect the already-cancelled entry. |
| foundation-concurrency-018 | retry-ceiling-default-and-floor | Construct a debouncer with a 5-second debounce and a 1-second retry ceiling. | Constructs without error; the effective ceiling used for backoff is 5 seconds (raised to match the debounce window), never the smaller 1 second passed in. |
| foundation-concurrency-019 | teardowns-confined-isolation, add-returns-immediately, drain-awaits-all-in-flight | Add a teardown that sleeps 150ms before recording `"slow"`. | Immediately after adding it, nothing is recorded; after `drain` returns, the tracker reports `"slow"` as finished. |
| foundation-concurrency-020 | drain-awaits-all-in-flight | Add five teardowns with staggered delays. | `drain` returns only once all five have recorded — five finished entries. |
| foundation-concurrency-021 | drain-awaits-teardowns-added-during-drain | An added teardown records `"outer"` and then itself adds a second teardown recording `"inner"`. | `drain` returns only after both have recorded, in order — `["outer", "inner"]`. |
| foundation-concurrency-022 | entry-self-removes-on-completion, in-flight-count-internal-visibility | Add a no-op teardown, drain, then add another no-op teardown without draining and wait past its completion. | The in-flight count is `0` after the drained case; it is `0` again after the un-drained instant teardown has had time to finish on its own. |
| foundation-concurrency-023 | drain-on-empty-returns-immediately | Call `drain` on a freshly constructed tracker with nothing added. | Returns promptly with no suspension; the in-flight count is `0`. |
| foundation-concurrency-024 | teardown-nonthrowing-closure | Attempt to add a teardown whose closure contains an unhandled failing call. | Fails to compile — a teardown cannot fail, so an unhandled failing call inside the closure is a compile error; the caller must handle it explicitly before returning. |
| foundation-concurrency-025 | cancel-all-keys | Schedule work for keys `"a"`, `"b"`, and `"c"` on one debouncer, then cancel all. | No key remains pending and none of the three closures ran. |

## Edge Cases

- **Null / empty input**: Adding a no-op teardown MUST be tracked and drained exactly like any other teardown. Scheduling work imposes no validation on the key type — an empty string key or any other "empty" value MUST be accepted and treated like any other key, since the debouncer performs no content inspection of it, only hashing and equality. The blocking-work helper imposes no validation on its closure or result type — a closure that returns immediately with a trivially empty value MUST be handled identically to any other closure.
- **Boundary values**: A `debounce` or `maximumRetryInterval` of zero MUST be accepted by construction — no lower bound is enforced beyond the floor already stated in `retry-ceiling-default-and-floor`; a zero debounce degenerates to running on (approximately) the next turn of its execution context rather than truly debouncing. The retry-backoff exponent shift is explicitly capped at 20 specifically so an entry that keeps failing for an extremely long time cannot overflow the underlying computation — this is a MUST, not incidental. The tracker's internal token counter increments once per added teardown with no wraparound handling.
- **Concurrent access**: The debouncer and the tracker MUST serialize every call to their own public operations through their single execution context — two callers invoking `schedule`/`cancel`/`add`/`drain` "concurrently" are actually serialized one at a time, with only suspension points as interleaving opportunities. The blocking-work helper holds no shared mutable state at all, so concurrent calls to `run` from any number of callers MUST be safe with no synchronization, per `blocking-calls-run-independently`.
- **Error states**: A debouncer work closure that fails MUST leave its entry pending and re-armed rather than lost, per `failure-keeps-entry-and-rearms` — this is the specific bug (a full disk, a revoked network volume silently dropping the pending save) the debouncer exists to fix. A teardown is non-throwing by design (`teardown-nonthrowing-closure`); one that encounters an internal error and wants that visible MUST catch and report it itself (e.g. by logging) before returning, since nothing in the tracker observes or surfaces it. The helper's throwing overload MUST propagate `work`'s error to the caller unchanged, per `blocking-throwing-resume`; its non-throwing overload has no error path at all, by the caller's choice of overload.
- **Offline / disconnected state**: Not applicable — none of the three utilities performs network access itself; each only decides where (the blocking-work helper) or when (the debouncer, the tracker) a caller-supplied closure runs. A closure whose own work involves a network call (none of the current call sites' closures do; they are file I/O, archive verification, or shutdown-time state teardown) would surface connectivity loss as a failure through the same paths already described under Error States, not through any offline-specific behavior these three utilities define.
- **Cancellation**: `run` MUST ignore cancellation of the calling operation once `work` is dispatched (`blocking-not-a-cancellation-point`) — a cancelled caller still waits for the full synchronous closure to return. Cancelling a debouncer key cancels the entry's timer and run cooperatively only; a `work` closure that never checks for cancellation and never reaches a cancellable suspension point MUST be allowed to keep running to completion after cancellation has already discarded its entry, per `cancellation-is-cooperative-only`. The tracker exposes no cancellation entry point at all; `drain` only awaits tracked teardowns, it never cancels one.
- **Owner deallocation while work is pending**: The debouncer's timer and run tasks each hold their owner weakly; if the last strong reference to a debouncer instance is released while a timer is armed or a run is executing, that step MUST no-op — the pending entries and their stored work closures are deallocated along with the debouncer, and neither the pending work nor an `onFailure` call ever happens. This is a SHOULD-level caller obligation, not a marker: a caller that needs every scheduled write to complete SHOULD flush all pending work before releasing its debouncer, exactly as draining the pending-teardowns tracker exists to guarantee for detached teardown work at the call sites that motivated it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `qos` (parameter to `run`) | quality-of-service class | `userInitiated` | The background queue's priority class the closure is dispatched to. |
| `work` (parameter to `run`) | closure, throwing or non-throwing | none — required | The synchronous, thread-blocking closure to run off the cooperative pool. |
| `debounce` (parameter to construction) | duration | 1 second | How long a key stays quiet before its scheduled work runs. |
| `maximumRetryInterval` (parameter to construction) | duration | 30 seconds, floored at `debounce` | Ceiling on the exponential backoff applied after a failed attempt. |
| `onFailure` (parameter to construction) | callback | none | Called once per failed attempt with the key and the error; the debouncer itself never logs. |
| `work` (parameter to `schedule`) | asynchronous, failable closure | none — required, per key | The work to (re-)schedule for `key`, replacing whatever was previously scheduled for it. |
| `teardown` (parameter to `add`) | asynchronous, non-failable closure | none — required | The fire-and-forget teardown to start and track. |

None of the three utilities reads an environment variable or a settings key; every value they operate on arrives as a construction or call parameter.

## Deep Linking

Not applicable: none of the three utilities defines a URL scheme, route, or navigation destination — they schedule and dispatch closures, not app navigation.

## Localization

Not applicable: none of the three utilities contains a user-facing string literal — each operates on a generic result type, key type, or opaque closure supplied by its caller, with no string of its own to localize.

## Accessibility Options

Not applicable: none of the three utilities presents UI, so none responds to Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of the three utilities contains a feature-flag or settings-key reference of its own.

## Analytics

Not applicable: none of the three utilities contains an analytics or event-tracking call.

## Privacy

- **Data handled**: None of the three utilities defines a data field of its own — each only carries whatever the caller's closure captures or returns. In practice that closure MAY handle sensitive data: a plugin installer's use of the blocking-work helper verifies a signature and digest inside the closure, and a document reloader's use reads arbitrary file contents that MAY be sensitive user documents. None of the three utilities itself inspects, parses, or branches on the content of any value passing through it.
- **Storage**: None of the three utilities persists anything; each holds a closure or a task handle only in memory for the duration of one dispatched call, one debounce cycle, or one teardown's execution.
- **Transmission**: None of the three utilities transmits data itself; whatever a wrapped closure does with the network (none of the current call sites' closures perform network I/O) is entirely outside these utilities.
- **Retention**: None — the blocking-work helper retains nothing past one call; a debouncer entry is retained only until it succeeds or is cancelled (with failed entries retained specifically so flushing all can find them at shutdown); a tracked teardown handle is retained only until its teardown completes.

## Logging

Not applicable: none of the three utilities calls any logging API. The debouncer's own contract states this explicitly for itself — it never logs; whoever owns the work owns how a failure is reported — and reports a failure only through the caller-supplied `onFailure` closure, which MAY log but is not required to.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/. |
