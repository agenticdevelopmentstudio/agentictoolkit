<!-- leaf: implement-sync-engine/triggers--part-2 · source: sync-engine-triggers.md -->

# SyncEngineTriggers — continued (part 2)

## Platform Notes

- **SwiftUI**: No SwiftUI-specific code. A SwiftUI host typically holds the sources in its app model, attaches them to the engine at launch, and fires the manual source from `.refreshable` or `.onChange(of: scenePhase)`; stop the periodic and connectivity sources when the model is torn down.
- **Compose**: Model `kicks` as a Kotlin `Flow<SyncKickReason>` (a `Channel(Channel.UNLIMITED)` exposed with `receiveAsFlow()` keeps the unbounded, single-consumer semantics). Periodic: a coroutine loop of `delay(interval)` then `send(Periodic)` in a scope cancelled by `stop()`. Connectivity: `callbackFlow` over `ConnectivityManager.registerDefaultNetworkCallback` with `NET_CAPABILITY_VALIDATED`; Android reports per-network `onAvailable`/`onLost` rather than a single path status, so the port must keep its own previous-status flag and suppress the initial callback. `SyncKickReason` becomes a sealed interface with a `HostSpecific(val value: String)` data class.
- **React/Web**: Expose `kicks` as an async iterable backed by a queue (or an `EventTarget`). Periodic: `setTimeout` re-armed after each yield (fixed delay), cleared by `stop()`; a `FinalizationRegistry` is the closest analogue to the Swift `deinit`, but it is not deterministic, so require explicit `stop()`. Connectivity: the `online`/`offline` window events and `navigator.onLine`; `online` already fires only on transition, and there is no initial event. JavaScript is single-threaded, so the previous-status flag has no ordering concern.
- **AppKit / UIKit**: This is the source platform; the code is framework-agnostic Swift using Swift Concurrency and Network.framework. `PeriodicTriggerSource.swift` drives ticks from an unstructured `Task` with `Task.sleep(for:)` and tears down in `deinit`. `ConnectivityTriggerSource.swift` is the only file in the target that imports Network, using `NWPathMonitor` on a caller-supplied `DispatchQueue` and a `nonisolated(unsafe)` previous-status flag; it works in daemons as well as apps. `ManualTriggerSource.swift` wraps a bare continuation. All three use `AsyncStream.makeStream(of:)` and declare `@unchecked Sendable`; the protocol and `SyncKickReason` live in `SyncProtocols.swift` and `SyncEvents.swift`.
- **WinUI 3**: Model `kicks` as `IAsyncEnumerable<SyncKickReason>` produced from `System.Threading.Channels.Channel.CreateUnbounded<SyncKickReason>(new UnboundedChannelOptions { SingleReader = true })`; `stop()` becomes `IDisposable.Dispose()` calling `writer.TryComplete()` so `await foreach` ends. Periodic: a `System.Threading.PeriodicTimer` loop in a `Task.Run`, cancelled through a `CancellationTokenSource`; note `PeriodicTimer` is fixed-rate, so for the source's fixed-delay behavior use `await Task.Delay(interval, token)` between writes instead. There is no deterministic `deinit`: require callers to dispose (a finalizer cannot safely await). Connectivity: subscribe to `Windows.Networking.Connectivity.NetworkInformation.NetworkStatusChanged` and read `NetworkInformation.GetInternetConnectionProfile()?.GetNetworkConnectivityLevel() == NetworkConnectivityLevel.InternetAccess` as "satisfied"; the event fires on a thread-pool thread and may fire concurrently, so guard the previous-status flag with a `lock` or `Interlocked.Exchange`, and unsubscribe in `Dispose`. `SyncKickReason` becomes an abstract record with `Periodic`, `ConnectivityRestored`, `Manual`, and `HostSpecific(string Value)` records, which gives value equality. `ObservableCollection` and `INotifyPropertyChanged` do not apply: nothing here is bound to UI.

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
