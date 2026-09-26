---
id: 82d3214f-620d-4fab-b817-f194d93ac296
title: SyncEngineTriggers
domain: agentictoolkit://cookbook/sync/triggers
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Kick sources that wake the sync engine: a fixed-interval ticker, a connectivity-restored
  watcher, and a host-driven manual trigger.'
platforms:
- swift
- macos
- ios
tags:
- sync
- offline
- engine
depends-on: []
related:
- agentictoolkit://cookbook/sync/sync-engine
- agentictoolkit://cookbook/adh-offline-sync-client
references:
- packages/apple/AgenticToolkit/Sync/Triggers/PeriodicTriggerSource.swift
- packages/apple/AgenticToolkit/Sync/Triggers/ConnectivityTriggerSource.swift
- packages/apple/AgenticToolkit/Sync/Triggers/ManualTriggerSource.swift
- packages/apple/AgenticToolkit/Sync/SyncProtocols.swift
- packages/apple/AgenticToolkit/Sync/SyncEvents.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitSyncTests/TriggerSourceTests.swift
approved-by: ''
approved-date: ''
---

# SyncEngineTriggers

## Overview

The trigger sources are the producers that tell the sync engine when to run a cycle. Each one conforms to the `SyncTriggerSource` protocol (declared in `SyncProtocols.swift`), whose only requirement is a `kicks: AsyncStream<SyncKickReason>` property. A host constructs one or more sources and hands each to `SyncEngine.attach(_:)`, which iterates the stream and calls `kick(reason:)` for every element (see [SyncEngine](agentictoolkit://cookbook/sync/sync-engine)).

Three concrete sources ship:

- `PeriodicTriggerSource` — yields `.periodic` once per fixed interval until stopped.
- `ConnectivityTriggerSource` — yields `.connectivityRestored` each time the network path goes from unsatisfied to satisfied.
- `ManualTriggerSource` — yields whatever reason the host passes to `fire(_:)`.

`SyncKickReason` (declared in `SyncEvents.swift`) is the value every source emits: `.periodic`, `.connectivityRestored`, `.manual`, or `.hostSpecific(String)`. It is `Sendable` and `Equatable`.

Use these when a host needs the engine to sync on a timer, on network recovery, or on demand (pull-to-refresh, app foregrounding, a push notification) without writing its own stream plumbing.

## Behavioral Requirements

### Shared contract

- **trigger-protocol**: A trigger source MUST expose a read-only `kicks` stream of `SyncKickReason` values; this is the only member `SyncTriggerSource` requires.
- **trigger-sendable**: Every trigger source type MUST be safe to share across concurrency domains; the protocol inherits `Sendable` and each concrete class declares `@unchecked Sendable`, relying on the stream continuation (and, for connectivity, the monitor queue) for thread safety.
- **kick-reason-cases**: `SyncKickReason` MUST have exactly four cases: `periodic`, `connectivityRestored`, `manual`, and `hostSpecific` carrying one `String` payload.
- **kick-reason-equality**: Two `SyncKickReason` values MUST compare equal only when they are the same case and, for `hostSpecific`, carry equal strings.
- **stream-created-at-init**: Each source MUST create its `kicks` stream and its continuation in its initializer, so the stream exists before any consumer subscribes.
- **unbounded-buffer**: Each source's stream MUST buffer every yielded reason until it is consumed; the streams are created with the default (unbounded) buffering policy, so no kick is dropped for a slow consumer.
- **single-consumer**: Each source's `kicks` stream MUST be consumed by a single iterating task; the stream is a unicast `AsyncStream` and is not a broadcast channel.
- **finish-ends-iteration**: After a source's continuation is finished, a consumer's pending or next iteration MUST return end-of-sequence once any already-buffered reasons are drained.
- **engine-stop-does-not-stop-source**: Stopping the engine MUST NOT stop an attached source; `SyncEngine.stop()` cancels only its own consuming tasks, so the host owns calling `stop()` on periodic and connectivity sources.

### PeriodicTriggerSource

- **periodic-init**: `PeriodicTriggerSource(interval:)` MUST start ticking immediately on construction, with no separate start call.
- **periodic-reason**: Every element a periodic source yields MUST be `.periodic`.
- **periodic-first-tick-delay**: The first `.periodic` MUST be yielded after one full `interval` has elapsed; there is no tick at construction time.
- **periodic-fixed-delay**: Each subsequent tick MUST be scheduled `interval` seconds after the previous yield (fixed delay, not fixed rate), so any scheduling lateness accumulates rather than being corrected.
- **periodic-stop-cancels**: `stop()` MUST cancel the ticking task so no further `.periodic` is yielded.
- **periodic-stop-finishes**: `stop()` MUST finish the stream so a consumer's iteration ends.
- **periodic-cancel-check**: After waking from each sleep, the ticking task MUST check for cancellation and exit without yielding if cancelled.
- **periodic-sleep-error**: A thrown error from the interval sleep MUST be discarded; the only error the sleep can throw is cancellation, which the post-sleep cancellation check then acts on.
- **periodic-deinit-stops**: Releasing the last strong reference to a periodic source MUST perform the same teardown as `stop()`; `deinit` calls `stop()`.
- **periodic-no-self-capture**: The ticking task MUST NOT retain the source instance; it captures only the local continuation, so the source can be deallocated while the task is running.
- **periodic-stop-idempotent**: Calling `stop()` more than once, including the implicit call from `deinit` after an explicit one, MUST have no additional effect.
- **periodic-interval-precondition**: A positive `interval` is a caller precondition. `init(interval:)` accepts any `TimeInterval` with no check; a zero or negative interval makes the sleep return at once, so the task yields `.periodic` in a tight loop into the unbounded buffer.

### ConnectivityTriggerSource

- **connectivity-init**: `ConnectivityTriggerSource(queue:)` MUST start monitoring the network path immediately on construction, delivering path updates on the supplied queue.
- **connectivity-default-queue**: When no queue is passed, the source MUST use a new serial dispatch queue labelled `ConnectivityTriggerSource`.
- **connectivity-reason**: Every element a connectivity source yields MUST be `.connectivityRestored`.
- **connectivity-transition-only**: The source MUST yield `.connectivityRestored` only when a path update reports satisfied and the immediately preceding update reported not satisfied.
- **connectivity-no-initial-kick**: The first path update after construction MUST NOT yield, whatever its status; with no previous observation there is no transition.
- **connectivity-unsatisfied-definition**: Any path status other than satisfied (including unsatisfied and requires-connection) MUST count as not satisfied.
- **connectivity-repeat-satisfied**: Consecutive satisfied updates MUST NOT yield more than once; only the first satisfied update after a not-satisfied one yields.
- **connectivity-stop-cancels**: `stop()` MUST cancel the path monitor so no further updates are processed.
- **connectivity-stop-finishes**: `stop()` MUST finish the stream so a consumer's iteration ends, even when called before any path update has arrived.
- **connectivity-no-deinit**: The connectivity source MUST NOT define a `deinit` teardown; unlike the periodic source, releasing it without calling `stop()` performs no explicit monitor cancellation or stream finish, so hosts call `stop()` themselves.
- **connectivity-queue-precondition**: A serial queue is a caller precondition. The previous-status flag is `nonisolated(unsafe)` and is read and written by every path update on the supplied queue; the default, `DispatchQueue(label: "ConnectivityTriggerSource")`, is serial, so the flag is ordered. A caller that passes a concurrent queue leaves the flag unordered.

### ManualTriggerSource

- **manual-fire**: `fire(_:)` MUST yield exactly the reason passed, unchanged, including `.hostSpecific` payloads and non-manual cases such as `.periodic`.
- **manual-fire-before-subscribe**: A reason fired before any consumer iterates MUST be buffered and delivered to the first `next()`.
- **manual-fire-any-thread**: `fire(_:)` MUST be callable from any thread or task without external synchronisation.
- **manual-no-stop**: The manual source MUST NOT provide a `stop()`; it holds no task or OS handle, and its stream is released with the instance.
- **manual-no-validation**: `fire(_:)` MUST accept any `SyncKickReason`, including `.hostSpecific("")`, without validation; interpretation of the reason belongs to the engine.

## Appearance

Not applicable — this is a set of sync kick-source classes, not a visual component.

## States

Not applicable — this is a set of sync kick-source classes, not a visual component.

## Accessibility

Not applicable — this is a set of sync kick-source classes, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| trig-001 | periodic-init, periodic-reason, periodic-fixed-delay | Construct a periodic source with `interval` 0.02; await two elements from one iterator (`testPeriodicTicks`) | Both elements are `.periodic` |
| trig-002 | periodic-first-tick-delay | Construct with `interval` 0.5; record the time of the first element | First element arrives no sooner than 0.5 s after construction |
| trig-003 | periodic-stop-cancels, periodic-stop-finishes, finish-ends-iteration | Interval 0.02; await one tick; call `stop()`; drain the iterator (`testPeriodicStopFinishesContinuation`) | Any already-buffered tick is returned, then iteration returns end-of-sequence instead of hanging |
| trig-004 | periodic-deinit-stops, periodic-no-self-capture | Hold the only strong reference in a box; await one tick; set the box to nil; drain (`testPeriodicDeinitStopsTicking`) | Iteration ends; the instance is deallocated while the task was running |
| trig-005 | periodic-stop-idempotent | Call `stop()` twice, then release the instance | No crash; the stream stays finished |
| trig-006 | periodic-cancel-check, periodic-sleep-error | Interval 10; call `stop()` 0.01 s later | Iteration ends promptly; no `.periodic` is ever yielded; no error surfaces to the consumer |
| trig-007 | connectivity-stop-finishes, connectivity-stop-cancels | Construct a connectivity source; call `stop()` immediately; drain (`testConnectivityStopFinishesContinuation`) | Iteration returns end-of-sequence without any element |
| trig-008 | connectivity-no-initial-kick | Path update sequence: satisfied | No element yielded |
| trig-009 | connectivity-transition-only, connectivity-reason, connectivity-init | Path update sequence: unsatisfied, satisfied | Exactly one `.connectivityRestored` |
| trig-010 | connectivity-repeat-satisfied | Path update sequence: unsatisfied, satisfied, satisfied | Exactly one `.connectivityRestored` |
| trig-011 | connectivity-transition-only | Path update sequence: satisfied, unsatisfied, satisfied, unsatisfied, satisfied | Exactly two `.connectivityRestored` |
| trig-012 | connectivity-unsatisfied-definition | Path update sequence: requires-connection, satisfied | Exactly one `.connectivityRestored` |
| trig-013 | connectivity-default-queue | Construct with no `queue` argument | Path updates are delivered on a serial queue labelled `ConnectivityTriggerSource` |
| trig-014 | manual-fire, manual-fire-before-subscribe | Create a manual source; make an iterator; `fire(.manual)`; await `next()` (`testManualFires`) | Returns `.manual` |
| trig-015 | manual-fire, manual-no-validation, kick-reason-equality | `fire(.hostSpecific("push"))` then `fire(.hostSpecific(""))` | Consumer receives `.hostSpecific("push")` then `.hostSpecific("")`, in that order; the first is not equal to `.hostSpecific("other")` |
| trig-016 | unbounded-buffer, stream-created-at-init | Manual source; fire 1,000 `.manual` before any iteration; then drain 1,000 | All 1,000 elements are delivered |
| trig-017 | manual-fire-any-thread | Fire 100 reasons concurrently from 10 tasks | Consumer receives exactly 100 elements; no crash |
| trig-018 | engine-stop-does-not-stop-source | Attach a periodic source to an engine; call `SyncEngine.stop()`; iterate the source directly | The source keeps yielding `.periodic` until its own `stop()` is called |
| trig-019 | kick-reason-cases, trigger-protocol, trigger-sendable | Compile a switch over `SyncKickReason` with no default; pass each source across a task boundary as `any SyncTriggerSource` | Compiles with exactly four cases; each source is accepted as `Sendable` |
| trig-020 | single-consumer | Iterate one source's `kicks` from one task and fire three reasons | That task receives all three in fire order |
| trig-021 | connectivity-no-deinit | Release a connectivity source without calling `stop()` | No explicit `stop()` runs; the source has no `deinit` |
| trig-022 | manual-no-stop | Inspect the manual source's public surface | Exposes `kicks`, `init()` and `fire(_:)` only; no `stop()` |

## Edge Cases

- **Zero or negative periodic interval**: the sleep returns immediately and the task yields `.periodic` in a tight loop into the unbounded buffer; see periodic-interval-precondition (MUST, as the source behaves).
- **Very large periodic interval**: the first tick is delayed by the full interval; `stop()` still cancels the sleep at once, so teardown is not delayed (MUST).
- **Stop before first tick**: calling `stop()` during the first sleep yields nothing and ends iteration (MUST).
- **Slow or absent consumer**: every source buffers without limit, so ticks accumulate in memory until consumed; the engine coalesces kicks that arrive during a running cycle, but the source itself never drops (MUST).
- **Released periodic source**: `deinit` calls `stop()`, so the consumer's iteration ends (MUST).
- **Released connectivity source without stop**: no explicit cancel or finish runs; teardown is left to deallocation of the monitor and continuation (MUST, as the source behaves).
- **Device already online at construction**: the first update is satisfied and yields nothing; a host wanting an immediate sync fires one through a manual source or calls the engine directly (MUST).
- **Flapping network**: every not-satisfied → satisfied transition yields one `.connectivityRestored`, with no debounce or rate limit; the engine's coalescing absorbs bursts (MUST).
- **Connectivity stop before any path update**: iteration ends with no element (MUST).
- **Concurrent queue passed to connectivity source**: the previous-status flag is unprotected; see connectivity-queue-precondition.
- **Concurrent `fire(_:)` calls**: each call yields once; the continuation serialises them, with no guaranteed order between calls from different tasks (MUST).
- **Empty `hostSpecific` payload**: `fire(.hostSpecific(""))` is yielded unchanged (MUST).
- **Multiple consumers of one stream**: not supported; `AsyncStream` is single-consumer and concurrent `next()` calls from two tasks are a runtime error (MUST NOT).
- **Engine stopped, source still running**: the source keeps producing into its buffer until the host stops or releases it (MUST).
- **Errors and offline state**: no source performs I/O that can fail; the connectivity source reports offline only by not yielding, and the periodic source keeps ticking while offline (MUST).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `PeriodicTriggerSource.init(interval:)` | `TimeInterval` (seconds) | none (required) | Delay before the first tick and between successive ticks |
| `ConnectivityTriggerSource.init(queue:)` | `DispatchQueue` | new serial queue labelled `ConnectivityTriggerSource` | Queue on which path updates are delivered and the transition flag is updated |
| `ManualTriggerSource.fire(_:)` | `SyncKickReason` | none (required) | The reason to yield to the consumer |

No environment variables, settings keys, or other injected dependencies are read.

## Deep Linking

Not applicable: the trigger sources are in-process stream producers with no URL, route, or navigable surface.

## Localization

Not applicable: no source contains a user-facing string; the `ConnectivityTriggerSource` queue label is an internal identifier and `hostSpecific` payloads are supplied by the host.

## Accessibility Options

Not applicable: the trigger sources render nothing and respond to no display option.

## Feature Flags

Not applicable: no source reads a flag; a host enables a trigger by constructing and attaching it.

## Analytics

Not applicable: no source records or emits analytics events; kicks surface only through the engine's `SyncEvent.started(_:)`.

## Privacy

Not applicable: the connectivity source reads only the satisfied/not-satisfied status of the network path, which it neither stores beyond one flag nor transmits, and the other sources touch no data.

## Logging

Not applicable: no source writes log output; the only observable signal is the `kicks` stream.

## Platform Notes

- **SwiftUI**: No SwiftUI-specific code. A SwiftUI host typically holds the sources in its app model, attaches them to the engine at launch, and fires the manual source from `.refreshable` or `.onChange(of: scenePhase)`; stop the periodic and connectivity sources when the model is torn down.
- **Compose**: Model `kicks` as a Kotlin `Flow<SyncKickReason>` (a `Channel(Channel.UNLIMITED)` exposed with `receiveAsFlow()` keeps the unbounded, single-consumer semantics). Periodic: a coroutine loop of `delay(interval)` then `send(Periodic)` in a scope cancelled by `stop()`. Connectivity: `callbackFlow` over `ConnectivityManager.registerDefaultNetworkCallback` with `NET_CAPABILITY_VALIDATED`; Android reports per-network `onAvailable`/`onLost` rather than a single path status, so the port must keep its own previous-status flag and suppress the initial callback. `SyncKickReason` becomes a sealed interface with a `HostSpecific(val value: String)` data class.
- **React/Web**: Expose `kicks` as an async iterable backed by a queue (or an `EventTarget`). Periodic: `setTimeout` re-armed after each yield (fixed delay), cleared by `stop()`; a `FinalizationRegistry` is the closest analogue to the Swift `deinit`, but it is not deterministic, so require explicit `stop()`. Connectivity: the `online`/`offline` window events and `navigator.onLine`; `online` already fires only on transition, and there is no initial event. JavaScript is single-threaded, so the previous-status flag has no ordering concern.
- **AppKit / UIKit**: This is the source platform; the code is framework-agnostic Swift using Swift Concurrency and Network.framework. `PeriodicTriggerSource.swift` drives ticks from an unstructured `Task` with `Task.sleep(for:)` and tears down in `deinit`. `ConnectivityTriggerSource.swift` is the only file in the target that imports Network, using `NWPathMonitor` on a caller-supplied `DispatchQueue` and a `nonisolated(unsafe)` previous-status flag; it works in daemons as well as apps. `ManualTriggerSource.swift` wraps a bare continuation. All three use `AsyncStream.makeStream(of:)` and declare `@unchecked Sendable`; the protocol and `SyncKickReason` live in `SyncProtocols.swift` and `SyncEvents.swift`.
- **WinUI 3**: Model `kicks` as `IAsyncEnumerable<SyncKickReason>` produced from `System.Threading.Channels.Channel.CreateUnbounded<SyncKickReason>(new UnboundedChannelOptions { SingleReader = true })`; `stop()` becomes `IDisposable.Dispose()` calling `writer.TryComplete()` so `await foreach` ends. Periodic: a `System.Threading.PeriodicTimer` loop in a `Task.Run`, cancelled through a `CancellationTokenSource`; note `PeriodicTimer` is fixed-rate, so for the source's fixed-delay behavior use `await Task.Delay(interval, token)` between writes instead. There is no deterministic `deinit`: require callers to dispose (a finalizer cannot safely await). Connectivity: subscribe to `Windows.Networking.Connectivity.NetworkInformation.NetworkStatusChanged` and read `NetworkInformation.GetInternetConnectionProfile()?.GetNetworkConnectivityLevel() == NetworkConnectivityLevel.InternetAccess` as "satisfied"; the event fires on a thread-pool thread and may fire concurrently, so guard the previous-status flag with a `lock` or `Interlocked.Exchange`, and unsubscribe in `Dispose`. `SyncKickReason` becomes an abstract record with `Periodic`, `ConnectivityRestored`, `Manual`, and `HostSpecific(string Value)` records, which gives value equality. `ObservableCollection` and `INotifyPropertyChanged` do not apply: nothing here is bound to UI.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Sync/Triggers/` |

## Design Decisions

**Decision**: Each trigger is a separate class behind a one-member `SyncTriggerSource` protocol rather than options on the engine.
**Rationale**: The engine attaches any number of sources through `attach(_:)`, so hosts can add their own (for example a push-notification source yielding `.hostSpecific`) without engine changes, and Network.framework stays confined to `ConnectivityTriggerSource.swift`.
**Approved**: pending

**Decision**: The periodic source tears itself down in `deinit`; the connectivity source does not, and the manual source has no `stop()` at all.
**Rationale**: The periodic task captures only the local continuation, so the source comment states that calling `stop()` from `deinit` "never resurrects `self`". The manual source's doc comment says it "Holds no resources (no task, no OS handle)", so there is nothing to stop. The connectivity source's lack of a `deinit` is the source as written; hosts call `stop()` explicitly.
**Approved**: pending

**Decision**: The connectivity source yields only on an observed not-satisfied → satisfied transition, never on the first update.
**Rationale**: The doc comment states it "Emits .connectivityRestored on each unsatisfied→satisfied transition". Starting the previous-status flag as unknown means launching online does not produce a spurious kick; hosts sync at launch by other means.
**Approved**: pending

**Decision**: Streams use unbounded buffering and sources do no debouncing.
**Rationale**: `AsyncStream.makeStream(of:)` is called without a buffering policy. Coalescing belongs to the engine, whose `kick(reason:)` folds any kick that arrives during a running cycle into one pending follow-up.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | partial | Performance |
| [reconnection-strategy](agenticdevelopercookbook://compliance/access-patterns#reconnection-strategy) | passed | Access Patterns |
| [offline-behavior](agenticdevelopercookbook://compliance/access-patterns#offline-behavior) | passed | Access Patterns |

Each source does one job behind the one-member `SyncTriggerSource` protocol, and the engine depends only on that protocol. `TriggerSourceTests` covers periodic ticking, periodic stop and deinit teardown, manual firing, and connectivity stop, but not the connectivity transition logic, which needs an injectable path monitor to test; coverage is therefore partial. The only error any source can meet is sleep cancellation, which the periodic loop discards and then acts on through its cancellation check. Resource efficiency is partial because a zero or negative periodic interval spins a tight loop into an unbounded buffer, and a connectivity source released without `stop()` gets no explicit monitor cancellation. The connectivity source is the engine's reconnection signal, and while offline the sources simply stop producing reconnection kicks rather than failing.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from the Apple trigger sources |
