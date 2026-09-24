---
id: 8e0d1a9d-27a1-4b5b-9a7d-5b9f9a5f7f2e
title: ExtensionEvent
domain: agentictoolkit://recipes/extension-host-vs-code-api-extension-event
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The extension host''s coalescing pub/sub relay behind every vscode.d.ts
  callable Event<T>: a fixed, non-trailing-edge window that merges same-window
  fires, drops fires with no listener, and delivers to each JSContext once.'
platforms:
  - swift
  - macos
tags:
  - extension-host
  - vscode-api
  - event-emitter
  - debounce
  - javascriptcore
  - mainactor
depends-on: []
related: []
references:
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionEvent.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadDiagnostics.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/ExtensionEventTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/ExtensionTestSupport.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ""
approved-date: ""
---

# ExtensionEvent

## Overview

`ExtensionEvent.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionEvent.swift`) is this extension host's port of VS Code's `DebounceEmitter` + `PauseableEmitter` + `Event.map` stack (`event.ts`, pinned commit `3addbda66f9e80c3ed1b943822ab823bb6747b02`), exposed to extensions as `vscode.d.ts`'s callable `Event<T>`. It gives every later `vscode` namespace event member (`onDidChangeDiagnostics` today; `onDidChangeTextDocument`, `onDidChangeActiveTextEditor`, `onDidChangeConfiguration` by design intent) one coalescing relay: `ExtensionEventEmitter<Payload>` accepts host-side `fire(_:)` calls, opens a fixed window of a caller-chosen width, merges every payload fired inside that window into one, and delivers the merged payload once per subscribed `JSContext` when the window closes. Three files make up the component: `ExtensionEventWindowScheduling`, the protocol seam a test replaces to close the window on demand instead of sleeping for a real delay; its two production/immediate conformers (`ExtensionEventTimerWindow`, `ExtensionEventImmediateWindow`); and `ExtensionEventEmitter` itself, which owns firing, merging, delivery, subscription, and per-owner teardown.

## Behavioral Requirements

- **main-actor-isolation**: `ExtensionEventWindowScheduling`, `ExtensionEventTimerWindow`, `ExtensionEventImmediateWindow`, and `ExtensionEventEmitter` MUST be declared `@MainActor`; every stored property read and write, and every method body, MUST execute on the main actor.
- **window-scheduling-required-no-default**: `ExtensionEventEmitter.init(path:delay:window:merge:map:)` MUST take `window` as a required parameter with no default value.
- **fixed-window-opens-once**: `fire(_:)` MUST open a new window (call `window.openWindow(closingAfter:onClose:)`) only when `windowIsOpen` is `false`; a `fire(_:)` call while a window is already open MUST NOT open a second window and MUST NOT extend or restart the existing one.
- **window-opens-unconditionally**: `fire(_:)` MUST open a window when none is open regardless of whether `registrations` is empty, so a zero-listener fire still consumes one `openWindow` call.
- **payload-dropped-with-no-listeners**: `fire(_:)` MUST append `payload` to `queue` only when `registrations` is non-empty at the time of the call; when `registrations` is empty, the payload MUST NOT be queued and MUST NOT be recoverable by a listener that subscribes later.
- **payload-queued-before-window-opens**: within one `fire(_:)` call, the payload MUST be appended to `queue` before `window.openWindow(closingAfter:onClose:)` is called, so a conformer whose `onClose` runs synchronously inside `openWindow` finds that call's payload already present.
- **window-closes-exactly-once-per-open**: each `openWindow` call MUST invoke its `onClose` closure exactly once; `closeWindow()` MUST set `windowIsOpen` back to `false` before doing anything else, so the next `fire(_:)` after a close opens a fresh window.
- **empty-queue-delivers-nothing**: `closeWindow()` MUST take no merge or delivery action when `queue` is empty at the time the window closes; listeners MUST NOT receive an empty-payload delivery in this case.
- **merge-once-per-window**: `closeWindow()` MUST pass the entire accumulated `queue` to the injected `merge` closure exactly once per window close, producing exactly one merged `Payload`, and MUST clear `queue` before that merged payload is delivered.
- **state-reset-before-delivery**: `windowIsOpen` MUST be reset to `false` and `queue` MUST be emptied before `deliver(_:)` runs, so a listener that throws, or that fires the same emitter re-entrantly during delivery, leaves the emitter able to open a new window on the very next `fire(_:)`.
- **delivery-snapshot-isolation**: `deliver(_:)` MUST iterate a `let` snapshot of `registrations` taken at the start of the call, and MUST skip (via a liveness re-check against the live `registrations` array) any registration in that snapshot that was removed during the same delivery loop.
- **mapped-value-cached-per-context**: `deliver(_:)` MUST call the injected `map` closure at most once per distinct `JSContext` reached during one delivery, reusing the cached `JSValue` for every other registration whose `listener.context` is the same `JSContext`.
- **unmappable-context-skipped**: when `map(payload, context)` returns `nil` for a registration's context, `deliver(_:)` MUST skip invoking that registration's listener and MUST log an error naming `path` and the context (via `VSCodeAPI.name(of:)`), then continue with the remaining registrations.
- **listener-throw-does-not-halt-delivery**: when `VSCodeAPI.call(...)` returns `.threw(let exception)` for a registration, `deliver(_:)` MUST log the exception's `toString()` (or `"<unprintable>"`) and MUST continue delivering to the remaining registrations in the snapshot.
- **unavailable-context-does-not-halt-delivery**: when `VSCodeAPI.call(...)` returns `.unavailable` for a registration, `deliver(_:)` MUST log `VSCodeAPI.dispatchUnavailableMessage(for:)` for that context and MUST continue delivering to the remaining registrations in the snapshot.
- **listener-count-reflects-registrations**: `listenerCount` MUST equal `registrations.count` at the time it is read.
- **subscribe-implements-callable-event-contract**: `subscribe(arguments:in:owner:)` MUST implement `vscode.d.ts`'s callable `Event<T>` signature `(listener, thisArgs?, disposables?) => Disposable`, reading `listener` from `arguments[0]`, `thisArgs` from `arguments[1]` when present, and `disposables` from `arguments[2]` when present.
- **subscribe-rejects-non-function-listener**: `subscribe(arguments:in:owner:)` MUST test `arguments.first` with `isInstance(of:)` against the calling context's own `Function` constructor, and when that test fails (including when `arguments` is empty or the `Function` constructor is unavailable) MUST call `VSCodeAPI.raise("\(path) requires a listener function.", in: context)` and MUST return without registering anything.
- **this-args-truthy-gate**: `subscribe(arguments:in:owner:)` MUST bind `arguments[1]` as `thisArgs` only when it is JavaScript-truthy (per `MainThreadDiagnostics.isFalsy(_:)` negated); a `null`, `undefined`, absent, `0`, `NaN`, or empty-string second argument MUST bind no `thisArgs`.
- **registration-identity-monotonic**: each successful `subscribe` call MUST assign the registration a distinct `identifier` from a monotonically incrementing counter (`nextIdentifier`), used to remove exactly that registration and no other on disposal.
- **disposable-removes-exactly-one-registration**: the `onDispose` closure passed to `VSCodeAPI.disposable(in:onDispose:)` MUST remove only the registration whose `identifier` matches the one assigned at subscribe time, leaving every other registration (including others from the same owner) untouched.
- **disposable-idempotence-delegated**: `subscribe` MUST return the `JSValue` produced by `VSCodeAPI.disposable(in:onDispose:)` unmodified, relying on that helper's own single-call-only `onDispose` guarantee rather than re-implementing idempotence.
- **disposable-creation-failure-rolls-back**: when `VSCodeAPI.disposable(in:onDispose:)` returns `nil`, `subscribe` MUST remove the registration it had just appended (by `identifier`) and MUST call `VSCodeAPI.raise(...)` with a message naming `path` and `VSCodeAPI.name(of: context)`, leaving no orphaned registration behind.
- **disposable-pushed-to-array-argument**: when `arguments.count > 2` and `arguments[2]` is a JavaScript array (`isArray == true`), `subscribe` MUST invoke that array's `push` method with the same disposable it returns; when `arguments[2]` is present but not an array, `subscribe` MUST NOT push anything to it and MUST NOT raise an error.
- **remove-listeners-by-owner**: `removeListeners(ownedBy:)` MUST remove every registration whose `owner` equals `ObjectIdentifier(owner)` and MUST leave every registration belonging to a different owner untouched, even when those registrations share the same emitter.
- **owner-held-weakly-by-identity-only**: `Registration.owner` MUST be stored as an `ObjectIdentifier`, never as a strong or weak reference to the owning object itself.
- **timer-window-schedules-once**: `ExtensionEventTimerWindow.openWindow(closingAfter:onClose:)` MUST schedule exactly one `DispatchQueue.main.asyncAfter` call for `.now() + delay` per invocation, and MUST invoke `onClose` on the main actor when that deadline elapses.
- **immediate-window-synchronous-close**: `ExtensionEventImmediateWindow.openWindow(closingAfter:onClose:)` MUST call `onClose()` synchronously, before `openWindow` returns, regardless of the `delay` argument's value.
- **window-scheduling-has-no-cancellation**: `ExtensionEventWindowScheduling` MUST declare no method to cancel a scheduled window; once `openWindow` is called, the emitter MUST NOT attempt to prevent or defer that window's eventual `onClose`.
- **logging-conformance**: `ExtensionEventEmitter` MUST conform to `Loggable`, exposing a computed `nonisolated static var logger` rather than a stored one.

## Appearance

Not applicable — this is the extension host's coalescing event emitter, not a visual component.

## States

Not applicable — this is the extension host's coalescing event emitter, not a visual component. Its only lifecycle-shaped behavior is the per-window sequence (open, accumulate, close, merge, deliver), which is captured under Behavioral Requirements rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's coalescing event emitter, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-event-001 | payload-queued-before-window-opens, window-opens-unconditionally | Subscribe one listener via `onDidChange`, then `fire(["a"])` once, using `ManualExtensionEventWindow` (window stays open until closed explicitly) | `window.hasOpenWindow == true` and delivery count is `0` immediately after `fire`; after `closeOpenWindows()`, delivery count becomes `1` — `ExtensionEventTests.nothingIsDeliveredWhenTheWindowOpens` |
| extension-event-002 | fixed-window-opens-once, merge-once-per-window, payload-queued-before-window-opens | Subscribe one listener, then `fire(["a"])`, `fire(["b"])`, `fire(["c"])` before closing the window | `window.openCount == 1`, `window.requestedDelays == [0.050]`; after `closeOpenWindows()`, exactly one delivery with payload `["a", "b", "c"]` — `ExtensionEventTests.threeFiresInOneWindowOpenOneWindowAndArriveTogether` |
| extension-event-003 | window-closes-exactly-once-per-open, state-reset-before-delivery | `fire(["first"])`, close the window, then `fire(["second"])`, close again | `window.openCount == 2`, two deliveries in order `["first"]` then `["second"]` — `ExtensionEventTests.aSecondFireAfterTheFirstWindowClosesOpensAnotherWindow` |
| extension-event-004 | payload-dropped-with-no-listeners, window-opens-unconditionally, empty-queue-delivers-nothing | `fire(["dropped"])` with zero listeners subscribed, then subscribe a listener, close the window, then `fire(["kept"])` and close again | `window.openCount == 1` after the first fire; delivery count stays `0` after the first close; after the second fire and close, delivery count is `1` with payload `["kept"]` — `ExtensionEventTests.anEventFiredWithNoListenersIsNotDeliveredToALaterSubscriber` |
| extension-event-005 | this-args-truthy-gate | Subscribe `function () { this.tag }` bound to a truthy object `{tag: 'bound'}`, and a second listener bound to `null`; `fire(["x"])`, close the window | The truthy-bound listener reads `this.tag == "bound"`; the `null`-bound listener's `this === boundTarget` evaluates to `false` — `ExtensionEventTests.aTruthyThisArgsIsBoundAndNullIsNot` |
| extension-event-006 | disposable-pushed-to-array-argument | Call `onDidChange(function(){}, null, bag)` where `bag` is a JavaScript array | `bag.length == 1` and `bag[0] === returnedDisposable` — `ExtensionEventTests.theDisposableIsBothReturnedAndPushedOntoTheDisposablesArray` |
| extension-event-007 | disposable-idempotence-delegated, disposable-removes-exactly-one-registration | Subscribe two listeners; `fire(["before"])` and close; call `.dispose()` on the first listener's disposable twice; `fire(["after"])` and close | `listenerCount` drops from `2` to `1` after the first `dispose()` call and stays `1` after the second; the disposed listener's counter stays at `1` while the surviving listener's counter reaches `2` — `ExtensionEventTests.disposingAListenerStopsItAndDisposingTwiceRemovesNothingElse` |
| extension-event-008 | listener-throw-does-not-halt-delivery, state-reset-before-delivery | Subscribe a listener that throws, then a listener that increments a counter; `fire(["first"])` and close; `fire(["second"])` and close | The counter reaches `1` after the first close and `2` after the second; `window.openCount == 2`, proving the throw neither stopped the second listener nor left the window flag stuck — `ExtensionEventTests.aThrowingListenerDoesNotStopTheOthersOrBreakTheNextWindow` |
| extension-event-009 | subscribe-rejects-non-function-listener | Call `onDidChange({})` (a plain object, not a function) | `VSCodeAPI.raise` is invoked with `"test.onDidChange requires a listener function."`, `context.exception` is set, and no registration is added (`listenerCount` unchanged) — traced to `subscribe(arguments:in:owner:)`'s `isInstance(of:)` guard; no dedicated test exists in the given sources, so this vector is derived directly from the guard's unconditional early return |
| extension-event-010 | remove-listeners-by-owner | Owner `A` and owner `B` each subscribe one listener on the same emitter; call `removeListeners(ownedBy: A)`; `fire(["x"])` and close | `listenerCount == 1` after the call; only `B`'s listener is invoked — traced directly to `removeListeners(ownedBy:)`'s `registrations.removeAll { $0.owner == key }`; no dedicated test exists in the given sources for this emitter, though the same method is exercised indirectly through a caller's `dispose()` in `MainThreadLanguageModelsTests.swift` (not among the given sources) |
| extension-event-011 | mapped-value-cached-per-context | Two listeners subscribed from the same `JSContext`; `map` is instrumented to count its own calls; `fire(["x"])` and close | `map` is called exactly once for that window despite two listeners sharing the context, and both listeners receive `JSValue`s that are the same object (`===`) — traced directly to `deliver(_:)`'s `mappedByContext` cache keyed by `ObjectIdentifier(context)`; no dedicated test exists in the given sources |
| extension-event-012 | window-scheduling-required-no-default, immediate-window-synchronous-close | Construct an `ExtensionEventEmitter` with `window: ExtensionEventImmediateWindow()`; subscribe a listener; `fire(["x"])` with no explicit "close" step | The listener is invoked before `fire` returns, because `ExtensionEventImmediateWindow.openWindow` calls `onClose` synchronously — traced directly to `ExtensionEventImmediateWindow.openWindow`'s body; no dedicated test exists in the given sources for this conformer against the emitter, though its own doc comment states the synchrony explicitly |

## Edge Cases

- **Null/empty input**: `fire(_:)` called with zero live registrations MUST drop the payload without queuing it, per **payload-dropped-with-no-listeners**; a listener that subscribes after such a fire never sees that payload (MUST).
- **Null/empty input**: `subscribe` called with an empty `arguments` array MUST fail the `isInstance(of:)` guard (since `arguments.first` is `nil`) and MUST raise the same "requires a listener function" message as a non-function first argument (MUST).
- **Null/empty input**: a `Payload` value that is itself an empty collection (e.g. `[]`) is still one queue entry; `closeWindow()`'s `queue.isEmpty` guard checks the number of queued entries, not whether any entry's contents are empty, so a window whose only fire carried an empty-collection payload still delivers that (empty) merged payload (MUST).
- **Boundary values**: a `delay` of `0` seconds is still scheduled through `DispatchQueue.main.asyncAfter(deadline: .now() + 0)` for `ExtensionEventTimerWindow` — it is queued onto the main run loop, not delivered synchronously within the `fire(_:)` call, unless the caller supplied `ExtensionEventImmediateWindow` instead (MUST).
- **Boundary values**: a single registration and a single fire is the minimum case that reaches delivery; it MUST be merged (`merge([payload])`) and mapped identically to a multi-fire, multi-listener window (MUST).
- **Concurrent access**: `ExtensionEventEmitter` is `@MainActor`-isolated with no internal locking; every stored property is read and mutated only on the main actor, so there is no data race to define behavior for (MUST).
- **Concurrent access**: a listener that calls `fire(_:)` on the same emitter re-entrantly from inside `deliver(_:)` MUST NOT corrupt the outer delivery: `windowIsOpen` and `queue` were already reset before `deliver(_:)` began, so the re-entrant `fire` opens a genuinely new window and queues into a fresh `queue`, while the outer `deliver(_:)` continues walking its own local snapshot of `registrations` taken before either call re-entered (MUST).
- **Concurrent access**: a listener that disposes another listener's registration from inside its own callback MUST NOT crash or skip an unrelated registration; `deliver(_:)`'s liveness re-check against the live `registrations` array (not the snapshot) is what makes the just-disposed registration's listener skipped rather than invoked (MUST).
- **Error states**: a listener that throws MUST be logged (exception `toString()`, or `"<unprintable>"` when that itself returns `nil`) and MUST NOT stop delivery to the remaining listeners in the same window, per **listener-throw-does-not-halt-delivery** (MUST).
- **Error states**: a registration whose `JSContext` has been torn down (so `VSCodeAPI.call` returns `.unavailable`) MUST be logged via `VSCodeAPI.dispatchUnavailableMessage(for:)` and MUST NOT stop delivery to the remaining listeners, per **unavailable-context-does-not-halt-delivery** (MUST).
- **Error states**: when `map(payload, context)` returns `nil` for a context, every listener registered in that context for this delivery MUST be skipped (not retried, not delivered `undefined`) with one error logged per skipped registration, per **unmappable-context-skipped** (MUST).
- **Error states**: when `VSCodeAPI.disposable(in:onDispose:)` fails, `subscribe` MUST roll back the registration it had just appended before raising, so a failed subscribe leaves `listenerCount` unchanged from before the call, per **disposable-creation-failure-rolls-back** (MUST).
- **Offline or disconnected state**: not applicable — `ExtensionEventEmitter` performs no network access; it relays payloads already produced in-process between the host and a `JSContext`, so there is no connectivity-loss case to define.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` | `String` | none (required) | The member's full dotted path (e.g. `"vscode.languages.onDidChangeDiagnostics"`); used only in refusal messages and log lines, per its own doc comment. |
| `delay` | `TimeInterval` | none (required) | The window's width in seconds; each event member picks its own — `0.050` for `vscode.languages.onDidChangeDiagnostics` per `MainThreadDiagnostics.onDidChangeDiagnosticsDelay`. |
| `window` | `ExtensionEventWindowScheduling` | none (required, no default) | The window-scheduling seam; production callers pass `ExtensionEventTimerWindow()`, tests pass a recording double such as `ManualExtensionEventWindow`. |
| `merge` | `([Payload]) -> Payload` | none (required) | Collapses one window's queued payloads into one merged payload; `vscode.languages.onDidChangeDiagnostics` passes `{ $0.flatMap { $0 } }`. |
| `map` | `@MainActor (Payload, JSContext) -> JSValue?` | none (required) | Builds the `JSValue` a listener in a given `JSContext` receives from the merged payload; returning `nil` skips that context's listeners for the delivery. |
| (subscribe call) `thisArgs` | `JSValue?` (2nd call argument) | unbound | Bound as the listener's `this` only when JavaScript-truthy, per **this-args-truthy-gate**. |
| (subscribe call) `disposables` | `JSValue?` (3rd call argument) | none | When a JavaScript array, receives the returned `Disposable` via `push`, per **disposable-pushed-to-array-argument**. |

## Deep Linking

Not applicable: `ExtensionEvent.swift` defines no URL, route, or navigable destination — it is an in-process pub/sub relay with no navigation surface.

## Localization

`subscribe`'s two refusal messages are hardcoded English string literals with no localization key, `String(localized:)` call, or String Catalog entry: `"\(path) requires a listener function."` and `"\(path) could not create a Disposable in context '\(VSCodeAPI.name(of: context))'."`. Both reach the extension as a thrown JavaScript error via `VSCodeAPI.raise`, so an extension author sees the literal English text regardless of locale. The three `Self.logger.error(...)` messages in `deliver(_:)` are likewise hardcoded English, but those reach only the host's own log, never the extension.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `<path> requires a listener function.` | Raised when `subscribe`'s first argument fails the `Function` instance check. |
| (none — literal only) | `<path> could not create a Disposable in context '<context name>'.` | Raised when `VSCodeAPI.disposable(in:onDispose:)` returns `nil`. |

## Accessibility Options

Not applicable: `ExtensionEvent.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available once an `ExtensionEventEmitter` is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent calls are the `OSLog` lines covered under Logging, which are diagnostic logging, not analytics events.

## Privacy

- **Data collected**: `ExtensionEventEmitter` collects no data of its own; it relays whatever `Payload` value a host-side caller fires (for `onDidChangeDiagnostics`, a list of changed `URL`s) to whichever `JSValue` listeners an extension has subscribed. It also holds each listener's `JSValue` and optional `thisArgs` `JSValue` strongly for the registration's lifetime, per its own doc comment on lifetime.
- **Storage**: `ExtensionEventEmitter` performs no storage of its own; `registrations` and `queue` are in-memory only and exist for the emitter's lifetime.
- **Transmission**: nothing here leaves the process; delivery is an in-process JavaScriptCore call from Swift into a `JSContext` the same process owns.
- **Retention**: a subscribed listener's `JSValue` (and the `JSContext` it keeps alive) is retained until its `Disposable` is disposed or `removeListeners(ownedBy:)` removes it; the doc comment on `ExtensionEventEmitter` states this explicitly as "not a cycle" but a real extension-outlives-host lifetime hazard that `removeListeners(ownedBy:)` exists to bound.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `ExtensionEventEmitter` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|
| `map(payload, context)` returns `nil` for a registration's context during delivery | error | `<path> could not build its event value in context '<context name>'; this listener is skipped` |
| A listener throws during delivery | error | `A <path> listener threw: <exception description or "<unprintable>">` |
| A listener's context cannot dispatch (`.unavailable`) during delivery | error | `A <path> listener could not be invoked: <VSCodeAPI.dispatchUnavailableMessage(for:)>` |

No other event in this file is logged: `subscribe`'s two refusals (non-function listener, disposable-creation failure) are surfaced to the extension as thrown/raised errors instead of being logged, per **subscribe-rejects-non-function-listener** and **disposable-creation-failure-rolls-back**.

## Platform Notes

- **SwiftUI**: not applicable to this file — `ExtensionEvent.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionEvent.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration, and its one given consumer, `MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window:)`, is also `@MainActor` and macOS-only.
- **Compose**: model `ExtensionEventEmitter<Payload>` as a Kotlin `class ExtensionEventEmitter<Payload>` confined to the main dispatcher, with `registrations` and `queue` as plain `MutableList`s guarded by that confinement (no `Mutex` needed, matching the source's own single-actor argument). `ExtensionEventWindowScheduling` becomes a functional interface `fun interface ExtensionEventWindowScheduling { fun openWindow(delay: Duration, onClose: () -> Unit) }`, with a `Handler.postDelayed`-backed production conformer standing in for `DispatchQueue.main.asyncAfter`, and a synchronous test double standing in for `ExtensionEventImmediateWindow`. The listener/`JSValue` pair becomes whatever callback type the host's own JavaScript engine binding (e.g. a J2V8 or Rhino function reference) exposes.
- **React/Web**: this component's own upstream is already TypeScript (`event.ts`'s `DebounceEmitter`/`PauseableEmitter`), so a web port is closer to restoring the original than translating it: an `EventEmitter`-style class with a `Map`-backed `registrations` collection, `setTimeout`/`clearTimeout` in place of the window seam (though upstream's real class never cancels either, matching **window-scheduling-has-no-cancellation**), and the callable `Event<T>` signature implemented as a plain function property rather than a class method, per `vscode.d.ts`'s own call-signature shape.
- **WinUI 3**: model `ExtensionEventEmitter<TPayload>` as a generic class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue` at the top of the method, since nothing else will catch a wrong-thread call at compile time the way Swift's `@MainActor` does). `ExtensionEventWindowScheduling` becomes an interface `IExtensionEventWindowScheduling { void OpenWindow(TimeSpan delay, Action onClose); }`, with a production conformer built on `DispatcherQueueTimer` (its `Tick` event fires `onClose` once, then `Stop()`s itself — there is no cancel exposed to the emitter, matching **window-scheduling-has-no-cancellation**) and a synchronous test double calling `onClose()` inline for the `ExtensionEventImmediateWindow` equivalent. `registrations` becomes a `List<Registration>` (a private record/struct, not an `ObservableCollection`, since nothing outside this type observes it), and `Payload`/`JSValue` become whatever the chosen JavaScript engine binding uses — ClearScript's `ScriptObject`, or Jint's `JsValue`, standing in for `JavaScriptCore.JSValue`; `System.Text.Json` has no role here since nothing in this file serializes.

## Design Decisions

**Decision**: `fire(_:)` queues the payload into `queue` before calling `window.openWindow(closingAfter:onClose:)`, reversing upstream's own statement order (`DebounceEmitter.fire` arms `setTimeout` before `PauseableEmitter.fire` decides whether to queue).
**Rationale**: upstream's order is safe only because a JavaScript `setTimeout` callback can never run synchronously within the call that scheduled it. `ExtensionEventWindowScheduling` makes no such promise — `ExtensionEventImmediateWindow` calls `onClose` inline, before `openWindow` returns — so opening the window first would run `closeWindow()` against a still-empty queue and lose that call's payload until the next `fire`. Queueing first closes that gap while still reproducing both of upstream's outcomes (the window opens unconditionally; a zero-listener fire is dropped, not queued) by guarding each separately instead of relying on one statement order.
**Approved**: pending

**Decision**: `ExtensionEventWindowScheduling` declares no cancellation method.
**Rationale**: upstream's `DebounceEmitter` never cancels a pending timer either — `event.ts`'s whole ruling is that a `fire` inside an open window does not touch the pending timer. Per the protocol's own doc comment, a seam that offered cancellation would invite a trailing-edge reimplementation this component exists to rule out.
**Approved**: pending

**Decision**: `subscribe` refuses a non-callable first argument by raising synchronously, where upstream (`event.ts`) validates nothing and instead throws once per delivery window from inside its own error handler.
**Rationale**: per the source's own doc comment, this follows `MainThreadCommands.swift`'s existing precedent for a callback argument, and turns a silent per-window failure the extension author never sees into one synchronous error at the call site they wrote — safe to test as `typeof === 'function'` here because this host has only one JavaScript realm.
**Approved**: pending

**Decision**: `deliver(_:)` builds the mapped `JSValue` once per distinct `JSContext` reached during a delivery, caching it for every other registration sharing that context, rather than once per listener.
**Rationale**: upstream hands every listener the same event object (one `super.fire(this._mergeFn(events))`); two listeners in one context should see one object. Two listeners in different contexts cannot share a `JSValue` at all — a `JSValue` belongs to its context — and an emitter is shared across extensions, so that case is real, not hypothetical.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because the file's only responsibilities are window timing (delegated to the injected `ExtensionEventWindowScheduling` seam), merging and mapping (both delegated to injected closures owned by each event member's own configuration, e.g. `MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter`), and JavaScript invocation semantics (delegated to `VSCodeAPI.call`/`VSCodeAPI.disposable`/`VSCodeAPI.raise`) — it reimplements none of those. `unit-test-coverage` is partial: the given `ExtensionEventTests.swift` suite thoroughly covers all four of the doc comment's named upstream mutations (fixed window, no leading edge, window reopening, drop-with-no-listeners) plus `thisArgs` truthiness, disposable dual-effect, dispose idempotence, and throw-survival, but no test in the given sources exercises `subscribe-rejects-non-function-listener`, `disposable-creation-failure-rolls-back`, `remove-listeners-by-owner`, or `mapped-value-cached-per-context` directly against this emitter. `explicit-error-handling` passes: every failure path (non-function listener, disposable-creation failure, listener throw, unavailable context, unmappable context) is either an explicit synchronous raise or a logged-and-continued delivery failure — nothing is swallowed silently. `secure-log-output` passes because no credential or secret value is ever read or logged by this file; the values logged (`path`, a context name, an exception's own description) are diagnostic identifiers, not user secrets. `no-hardcoded-strings` fails because `subscribe`'s two raised messages, and `deliver`'s three logged messages, are English literals with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
