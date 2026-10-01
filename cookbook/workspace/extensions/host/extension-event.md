---
id: 8e0d1a9d-27a1-4b5b-9a7d-5b9f9a5f7f2e
title: Extension Event
domain: agentictoolkit://cookbook/workspace/extensions/host/extension-event
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The extension host''s coalescing pub/sub relay behind every vscode.d.ts
  callable Event<T>: a fixed, non-trailing-edge window that merges same-window
  fires, drops fires with no listener, and delivers to each JavaScript context once.'
platforms:
  - swift
  - macos
tags:
  - extension-host
  - vscode-api
  - event-emitter
  - debounce
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

# Extension Event

## Overview

This component is this extension host's port of VS Code's `DebounceEmitter` + `PauseableEmitter` + `Event.map` stack (`event.ts`, pinned commit `3addbda66f9e80c3ed1b943822ab823bb6747b02`), exposed to extensions as `vscode.d.ts`'s callable `Event<T>`. It gives every later `vscode` namespace event member (`onDidChangeDiagnostics` today; `onDidChangeTextDocument`, `onDidChangeActiveTextEditor`, `onDidChangeConfiguration` by design intent) one coalescing relay: the emitter accepts host-side fire calls, opens a fixed window of a caller-chosen width, merges every payload fired inside that window into one, and delivers the merged payload once per subscribed JavaScript context when the window closes. Three roles make up the component: the window-scheduling seam, which a test replaces to close the window on demand instead of sleeping for a real delay; its two production/immediate conformers; and the emitter itself, which owns firing, merging, delivery, subscription, and per-owner teardown.

## Behavioral Requirements

- **single-context-confinement**: The window-scheduling seam, its production and immediate conformers, and the emitter MUST all confine every stored-property read and write, and every method body, to a single execution context (see Platform Notes for how the source enforces this).
- **window-scheduling-required-no-default**: The emitter's initializer MUST take the window-scheduling seam as a required parameter with no default value.
- **fixed-window-opens-once**: Firing the emitter MUST open a new window (invoke the window-scheduling seam's open-window operation) only when no window is currently open; a fire call while a window is already open MUST NOT open a second window and MUST NOT extend or restart the existing one.
- **window-opens-unconditionally**: Firing the emitter MUST open a window when none is open regardless of whether any listener is currently registered, so a zero-listener fire still consumes one open-window call.
- **payload-dropped-with-no-listeners**: Firing the emitter MUST append the payload to the queue only when at least one listener is registered at the time of the call; when no listener is registered, the payload MUST NOT be queued and MUST NOT be recoverable by a listener that subscribes later.
- **payload-queued-before-window-opens**: Within one fire call, the payload MUST be appended to the queue before the window-scheduling seam's open-window operation is invoked, so a conformer whose close callback runs synchronously inside that call finds that call's payload already present.
- **window-closes-exactly-once-per-open**: Each open-window call MUST invoke its close callback exactly once; closing the window MUST clear the open-window flag before doing anything else, so the next fire after a close opens a fresh window.
- **empty-queue-delivers-nothing**: Closing the window MUST take no merge or delivery action when the queue is empty at the time the window closes; listeners MUST NOT receive an empty-payload delivery in this case.
- **merge-once-per-window**: Closing the window MUST pass the entire accumulated queue to the injected merge function exactly once per window close, producing exactly one merged payload, and MUST clear the queue before that merged payload is delivered.
- **state-reset-before-delivery**: The open-window flag MUST be cleared and the queue MUST be emptied before delivery runs, so a listener that throws, or that fires the same emitter re-entrantly during delivery, leaves the emitter able to open a new window on the very next fire.
- **delivery-snapshot-isolation**: Delivery MUST iterate a fixed snapshot of the registration list taken at the start of the call, and MUST skip (via a liveness re-check against the live registration list) any registration in that snapshot that was removed during the same delivery loop.
- **mapped-value-cached-per-context**: Delivery MUST call the injected map function at most once per distinct JavaScript context reached during one delivery, reusing the cached JavaScript value for every other registration whose listener shares that same context.
- **unmappable-context-skipped**: When the map function returns nothing for a registration's context, delivery MUST skip invoking that registration's listener and MUST log an error naming the emitter's path and the context, then continue with the remaining registrations.
- **listener-throw-does-not-halt-delivery**: When invoking a registration's listener throws, delivery MUST log the exception's description (or a placeholder when no description is available) and MUST continue delivering to the remaining registrations in the snapshot.
- **unavailable-context-does-not-halt-delivery**: When a registration's context can no longer be dispatched to, delivery MUST log that unavailability for that context and MUST continue delivering to the remaining registrations in the snapshot.
- **listener-count-reflects-registrations**: The listener count MUST equal the number of registrations at the time it is read.
- **subscribe-implements-callable-event-contract**: Subscribing MUST implement `vscode.d.ts`'s callable `Event<T>` signature `(listener, thisArgs?, disposables?) => Disposable`, reading the listener from the first call argument, `thisArgs` from the second when present, and `disposables` from the third when present.
- **subscribe-rejects-non-function-listener**: Subscribing MUST test the first call argument against the calling context's own function type, and when that test fails (including when no arguments were given or the function type is unavailable) MUST raise an error stating that the member requires a listener function, and MUST return without registering anything.
- **this-args-truthy-gate**: Subscribing MUST bind the second call argument as `thisArgs` only when it is JavaScript-truthy; a `null`, `undefined`, absent, `0`, `NaN`, or empty-string second argument MUST bind no `thisArgs`.
- **registration-identity-monotonic**: Each successful subscribe call MUST assign the registration a distinct identifier from a monotonically incrementing counter, used to remove exactly that registration and no other on disposal.
- **disposable-removes-exactly-one-registration**: The close callback passed when creating the returned `Disposable` MUST remove only the registration whose identifier matches the one assigned at subscribe time, leaving every other registration (including others from the same owner) untouched.
- **disposable-idempotence-delegated**: Subscribing MUST return the `Disposable` value produced by the shared disposable-creation helper unmodified, relying on that helper's own single-call-only guarantee rather than re-implementing idempotence.
- **disposable-creation-failure-rolls-back**: When the shared disposable-creation helper fails to produce a `Disposable`, subscribing MUST remove the registration it had just appended (by identifier) and MUST raise an error naming the member's path and the context, leaving no orphaned registration behind.
- **disposable-pushed-to-array-argument**: When a third call argument is present and is a JavaScript array, subscribing MUST invoke that array's `push` operation with the same `Disposable` it returns; when a third argument is present but not an array, subscribing MUST NOT push anything to it and MUST NOT raise an error.
- **remove-listeners-by-owner**: Removing listeners by owner MUST remove every registration whose owner matches the given owner's identity and MUST leave every registration belonging to a different owner untouched, even when those registrations share the same emitter.
- **owner-held-weakly-by-identity-only**: A registration's owner MUST be stored as an opaque identity reference, never as a strong or weak reference to the owning object itself.
- **timer-window-schedules-once**: The timer-backed window scheduler's open-window operation MUST schedule exactly one delayed callback for the configured delay per invocation, and MUST invoke the close callback on the same single execution context when that delay elapses.
- **immediate-window-synchronous-close**: The immediate window scheduler's open-window operation MUST invoke the close callback synchronously, before the open-window call returns, regardless of the delay value.
- **window-scheduling-has-no-cancellation**: The window-scheduling seam MUST declare no operation to cancel a scheduled window; once a window is opened, the emitter MUST NOT attempt to prevent or defer that window's eventual close.
- **logging-conformance**: The emitter MUST conform to the shared logging role used across the extension host, exposing its logger as a type-level property rather than a stored instance property.

## Appearance

Not applicable — this is the extension host's coalescing event emitter, not a visual component.

## States

Not applicable — this is the extension host's coalescing event emitter, not a visual component. Its only lifecycle-shaped behavior is the per-window sequence (open, accumulate, close, merge, deliver), which is captured under Behavioral Requirements rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's coalescing event emitter, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-event-001 | payload-queued-before-window-opens, window-opens-unconditionally | Subscribe one listener via the event member; fire the emitter once with payload `["a"]`, using a manually-closed window scheduler (window stays open until closed explicitly) | The window is open and the delivery count is 0 immediately after firing; after the window is closed, the delivery count becomes 1 — `ExtensionEventTests.nothingIsDeliveredWhenTheWindowOpens` |
| extension-event-002 | fixed-window-opens-once, merge-once-per-window, payload-queued-before-window-opens | Subscribe one listener, then fire the emitter three times with payloads "a", "b", "c" before closing the window | Exactly one window opens, requesting a delay of `0.050` seconds; after the window closes, exactly one delivery occurs with the merged payload `["a", "b", "c"]` — `ExtensionEventTests.threeFiresInOneWindowOpenOneWindowAndArriveTogether` |
| extension-event-003 | window-closes-exactly-once-per-open, state-reset-before-delivery | Fire the emitter with payload "first", close the window, then fire with payload "second", close again | Two windows open in sequence; two deliveries occur, in order, with payloads `["first"]` then `["second"]` — `ExtensionEventTests.aSecondFireAfterTheFirstWindowClosesOpensAnotherWindow` |
| extension-event-004 | payload-dropped-with-no-listeners, window-opens-unconditionally, empty-queue-delivers-nothing | Fire the emitter with payload "dropped" with zero listeners subscribed, then subscribe a listener, close the window, then fire with payload "kept" and close again | One window opens after the first fire; the delivery count stays 0 after the first close; after the second fire and close, the delivery count is 1, with payload `["kept"]` — `ExtensionEventTests.anEventFiredWithNoListenersIsNotDeliveredToALaterSubscriber` |
| extension-event-005 | this-args-truthy-gate | Subscribe a listener bound to a truthy object `{tag: 'bound'}`, and a second listener bound to `null`; fire the emitter with payload "x", close the window | The truthy-bound listener's this-value has `tag` equal to `"bound"`; the null-bound listener's this-value is not the same object as the intended bound target — `ExtensionEventTests.aTruthyThisArgsIsBoundAndNullIsNot` |
| extension-event-006 | disposable-pushed-to-array-argument | Call the event member with a listener function, `null`, and a JavaScript array as the third argument | The array's length becomes 1, and its one entry is the same object as the returned `Disposable` — `ExtensionEventTests.theDisposableIsBothReturnedAndPushedOntoTheDisposablesArray` |
| extension-event-007 | disposable-idempotence-delegated, disposable-removes-exactly-one-registration | Subscribe two listeners; fire with payload "before" and close; dispose the first listener's `Disposable` twice; fire with payload "after" and close | The listener count drops from 2 to 1 after the first dispose call and stays 1 after the second; the disposed listener's counter stays at 1 while the surviving listener's counter reaches 2 — `ExtensionEventTests.disposingAListenerStopsItAndDisposingTwiceRemovesNothingElse` |
| extension-event-008 | listener-throw-does-not-halt-delivery, state-reset-before-delivery | Subscribe a listener that throws, then a listener that increments a counter; fire with payload "first" and close; fire with payload "second" and close | The counter reaches 1 after the first close and 2 after the second; two windows opened in total, proving the throw neither stopped the second listener nor left the open-window flag stuck — `ExtensionEventTests.aThrowingListenerDoesNotStopTheOthersOrBreakTheNextWindow` |
| extension-event-009 | subscribe-rejects-non-function-listener | Call the event member with a plain object (not a function) as the listener | An error is raised stating `"test.onDidChange requires a listener function."`, the calling context's exception is set, and no registration is added (the listener count is unchanged) — traced to the subscribe operation's function-type guard; no dedicated test exists in the given sources, so this vector is derived directly from the guard's unconditional early return |
| extension-event-010 | remove-listeners-by-owner | Owner A and owner B each subscribe one listener on the same emitter; remove listeners owned by A; fire with payload "x" and close | The listener count is 1 after the call; only B's listener is invoked — traced directly to the remove-listeners-by-owner operation's filtering logic; no dedicated test exists in the given sources for this emitter, though the same operation is exercised indirectly through a caller's dispose() in a different test file (not among the given sources) |
| extension-event-011 | mapped-value-cached-per-context | Two listeners subscribed from the same JavaScript context; the map function is instrumented to count its own calls; fire with payload "x" and close | The map function is called exactly once for that window despite two listeners sharing the context, and both listeners receive JavaScript values that are the same object — traced directly to delivery's per-context cache; no dedicated test exists in the given sources |
| extension-event-012 | window-scheduling-required-no-default, immediate-window-synchronous-close | Construct the emitter with the immediate window scheduler; subscribe a listener; fire with payload "x" with no explicit "close" step | The listener is invoked before the fire call returns, because the immediate window scheduler's open-window operation calls its close callback synchronously — traced directly to that conformer's own body; no dedicated test exists in the given sources for this conformer against the emitter, though its own doc comment states the synchrony explicitly |

## Edge Cases

- **Null/empty input**: Firing the emitter with zero live registrations MUST drop the payload without queuing it, per **payload-dropped-with-no-listeners**; a listener that subscribes after such a fire never sees that payload (MUST).
- **Null/empty input**: Subscribing with no call arguments MUST fail the function-type guard (since there is no first argument to test) and MUST raise the same "requires a listener function" message as a non-function first argument (MUST).
- **Null/empty input**: A payload value that is itself an empty collection (e.g. `[]`) is still one queue entry; closing the window's empty-queue guard checks the number of queued entries, not whether any entry's contents are empty, so a window whose only fire carried an empty-collection payload still delivers that (empty) merged payload (MUST).
- **Boundary values**: A delay of `0` seconds is still scheduled asynchronously by the timer-backed window scheduler — it is queued onto the main run loop, not delivered synchronously within the fire call, unless the caller supplied the immediate window scheduler instead (MUST).
- **Boundary values**: A single registration and a single fire is the minimum case that reaches delivery; it MUST be merged (passing a one-element queue to the merge function) and mapped identically to a multi-fire, multi-listener window (MUST).
- **Concurrent access**: The emitter is confined to a single execution context with no internal locking; every stored property is read and mutated only within that context, so there is no data race to define behavior for (MUST).
- **Concurrent access**: A listener that fires the same emitter re-entrantly from inside delivery MUST NOT corrupt the outer delivery: the open-window flag and the queue were already reset before delivery began, so the re-entrant fire opens a genuinely new window and queues into a fresh queue, while the outer delivery continues walking its own local snapshot of registrations taken before either call re-entered (MUST).
- **Concurrent access**: A listener that disposes another listener's registration from inside its own callback MUST NOT crash or skip an unrelated registration; delivery's liveness re-check against the live registration list (not the snapshot) is what makes the just-disposed registration's listener skipped rather than invoked (MUST).
- **Error states**: A listener that throws MUST be logged (the exception's description, or a placeholder when no description is available) and MUST NOT stop delivery to the remaining listeners in the same window, per **listener-throw-does-not-halt-delivery** (MUST).
- **Error states**: A registration whose JavaScript context has been torn down MUST be logged with a message describing that unavailability and MUST NOT stop delivery to the remaining listeners, per **unavailable-context-does-not-halt-delivery** (MUST).
- **Error states**: When the map function returns nothing for a context, every listener registered in that context for this delivery MUST be skipped (not retried, not delivered an empty value) with one error logged per skipped registration, per **unmappable-context-skipped** (MUST).
- **Error states**: When the shared disposable-creation helper fails, subscribing MUST roll back the registration it had just appended before raising, so a failed subscribe leaves the listener count unchanged from before the call, per **disposable-creation-failure-rolls-back** (MUST).
- **Offline or disconnected state**: Not applicable — this component performs no network access; it relays payloads already produced in-process between the host and a JavaScript context, so there is no connectivity-loss case to define.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Path | string | none (required) | The member's full dotted path (e.g. `"vscode.languages.onDidChangeDiagnostics"`); used only in refusal messages and log lines, per its own doc comment. |
| Delay | time interval (seconds) | none (required) | The window's width in seconds; each event member picks its own — `0.050` for `vscode.languages.onDidChangeDiagnostics`. |
| Window scheduler | window-scheduling seam | none (required, no default) | The window-scheduling seam; production callers pass the timer-backed scheduler, tests pass a recording double. |
| Merge function | function from a list of payloads to one payload | none (required) | Collapses one window's queued payloads into one merged payload; `vscode.languages.onDidChangeDiagnostics` passes a flattening function. |
| Map function | function from (payload, JavaScript context) to an optional JavaScript value | none (required) | Builds the JavaScript value a listener in a given context receives from the merged payload; returning nothing skips that context's listeners for the delivery. |
| (subscribe call) `thisArgs` | second call argument | unbound | Bound as the listener's `this` only when JavaScript-truthy, per **this-args-truthy-gate**. |
| (subscribe call) `disposables` | third call argument | none | When a JavaScript array, receives the returned `Disposable` via `push`, per **disposable-pushed-to-array-argument**. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable destination — it is an in-process pub/sub relay with no navigation surface.

## Localization

Subscribing's two refusal messages are hardcoded English string literals with no localization key or platform localization mechanism: `"<path> requires a listener function."` and `"<path> could not create a Disposable in context '<context name>'."` Both reach the extension as a thrown JavaScript error, so an extension author sees the literal English text regardless of locale. The three error messages logged during delivery are likewise hardcoded English, but those reach only the host's own log, never the extension.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `<path> requires a listener function.` | Raised when subscribing's first argument fails the function-type check. |
| (none — literal only) | `<path> could not create a Disposable in context '<context name>'.` | Raised when the shared disposable-creation helper returns nothing. |

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available once an emitter is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent calls are the log lines covered under Logging, which are diagnostic logging, not analytics events.

## Privacy

- **Data collected**: This component collects no data of its own; it relays whatever payload value a host-side caller fires (for `onDidChangeDiagnostics`, a list of changed file URLs) to whichever JavaScript listeners an extension has subscribed. It also holds each listener's JavaScript value and optional `thisArgs` JavaScript value strongly for the registration's lifetime, per its own doc comment on lifetime.
- **Storage**: This component performs no storage of its own; the registration list and the queue are in-memory only and exist for the emitter's lifetime.
- **Transmission**: Nothing here leaves the process; delivery is an in-process call from the host into a JavaScript context the same process owns.
- **Retention**: A subscribed listener's JavaScript value (and the JavaScript context it keeps alive) is retained until its `Disposable` is disposed or listeners are removed by owner; the source's own doc comment states this explicitly as "not a cycle" but a real extension-outlives-host lifetime hazard that removing listeners by owner exists to bound.

## Logging

Subsystem: the app's bundle identifier (falling back to a placeholder when unavailable) | Category: derived from this component's type name

| Event | Level | Message |
|-------|-------|---------|
| The map function returns nothing for a registration's context during delivery | error | `<path> could not build its event value in context '<context name>'; this listener is skipped` |
| A listener throws during delivery | error | `A <path> listener threw: <exception description or "<unprintable>">` |
| A listener's context cannot dispatch during delivery | error | `A <path> listener could not be invoked: <unavailability message>` |

No other event in this file is logged: subscribing's two refusals (non-function listener, disposable-creation failure) are surfaced to the extension as thrown/raised errors instead of being logged, per **subscribe-rejects-non-function-listener** and **disposable-creation-failure-rolls-back**.

## Platform Notes

- **SwiftUI**: not applicable to this file — the source imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionEvent.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. The emitter is named `ExtensionEventEmitter<Payload>`; the window-scheduling seam is `ExtensionEventWindowScheduling`, with `ExtensionEventTimerWindow` as its production conformer (wrapping `DispatchQueue.main.asyncAfter(deadline: .now() + delay)`) and `ExtensionEventImmediateWindow` as the synchronous conformer used by construction-time tests; `ManualExtensionEventWindow` in the test target is a third, manually-triggered conformer. `ExtensionEventEmitter`, `ExtensionEventWindowScheduling`, `ExtensionEventTimerWindow`, and `ExtensionEventImmediateWindow` are all declared `@MainActor`. The "JavaScript context" and "JavaScript value" named throughout the normative text above are this file's `JavaScriptCore.JSContext` and `JavaScriptCore.JSValue`; dispatch into them goes through `VSCodeAPI.call(...)`, `VSCodeAPI.raise(...)`, `VSCodeAPI.disposable(in:onDispose:)`, `VSCodeAPI.name(of:)`, and `VSCodeAPI.dispatchUnavailableMessage(for:)` — this repo's own thin JavaScriptCore-dispatch helper, not part of `vscode.d.ts` itself. Subscribing's function-type guard is `arguments.first.isInstance(of:)` tested against the calling context's own `Function` constructor; its truthiness check for `thisArgs` is `MainThreadDiagnostics.isFalsy(_:)`, negated. A registration's owner is stored as an `ObjectIdentifier`. The initializer's exact signature is `ExtensionEventEmitter.init(path:delay:window:merge:map:)`; the open-window flag is the stored property `windowIsOpen`, the queue is `queue`, the registration list is `registrations`, and the monotonically incrementing counter is `nextIdentifier`. `ExtensionEventEmitter` conforms to `Loggable`, exposing a computed `nonisolated static var logger` (subsystem `Bundle.main.bundleIdentifier`, falling back to `"nil"`; category `ExtensionEventEmitter`, derived from the type name via `Loggable`'s default) rather than a stored logger, and every logged message during delivery is emitted through `OSLog` via that logger. Its one given consumer, `MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window:)`, is also `@MainActor` and macOS-only.
- **Compose**: model `ExtensionEventEmitter<Payload>` as a Kotlin `class ExtensionEventEmitter<Payload>` confined to the main dispatcher, with `registrations` and `queue` as plain `MutableList`s guarded by that confinement (no `Mutex` needed, matching the source's own single-actor argument). `ExtensionEventWindowScheduling` becomes a functional interface `fun interface ExtensionEventWindowScheduling { fun openWindow(delay: Duration, onClose: () -> Unit) }`, with a `Handler.postDelayed`-backed production conformer standing in for `DispatchQueue.main.asyncAfter`, and a synchronous test double standing in for `ExtensionEventImmediateWindow`. The listener/`JSValue` pair becomes whatever callback type the host's own JavaScript engine binding (e.g. a J2V8 or Rhino function reference) exposes.
- **React/Web**: this component's own upstream is already TypeScript (`event.ts`'s `DebounceEmitter`/`PauseableEmitter`), so a web port is closer to restoring the original than translating it: an `EventEmitter`-style class with a `Map`-backed `registrations` collection, `setTimeout`/`clearTimeout` in place of the window seam (though upstream's real class never cancels either, matching **window-scheduling-has-no-cancellation**), and the callable `Event<T>` signature implemented as a plain function property rather than a class method, per `vscode.d.ts`'s own call-signature shape.
- **WinUI 3**: model `ExtensionEventEmitter<TPayload>` as a generic class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue` at the top of the method, since nothing else will catch a wrong-thread call at compile time the way Swift's `@MainActor` does). `ExtensionEventWindowScheduling` becomes an interface `IExtensionEventWindowScheduling { void OpenWindow(TimeSpan delay, Action onClose); }`, with a production conformer built on `DispatcherQueueTimer` (its `Tick` event fires `onClose` once, then `Stop()`s itself — there is no cancel exposed to the emitter, matching **window-scheduling-has-no-cancellation**) and a synchronous test double calling `onClose()` inline for the `ExtensionEventImmediateWindow` equivalent. `registrations` becomes a `List<Registration>` (a private record/struct, not an `ObservableCollection`, since nothing outside this type observes it), and `Payload`/`JSValue` become whatever the chosen JavaScript engine binding uses — ClearScript's `ScriptObject`, or Jint's `JsValue`, standing in for `JavaScriptCore.JSValue`; `System.Text.Json` has no role here since nothing in this file serializes.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionEvent.swift` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/host/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
