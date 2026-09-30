<!-- leaf: implement-extension-host-vs-1/code-api-extension-event · source: extension-host-vs-code-api-extension-event.md -->

**Rules** (cite as `implement-extension-host-vs-1/code-api-extension-event#<slug>`):

- `main-actor-isolation` MUST
- `window-scheduling-required-no-default` MUST
- `fixed-window-opens-once` MUST
- `window-opens-unconditionally` MUST
- `payload-dropped-with-no-listeners` MUST
- `payload-queued-before-window-opens` MUST
- `window-closes-exactly-once-per-open` MUST
- `empty-queue-delivers-nothing` MUST
- `merge-once-per-window` MUST
- `state-reset-before-delivery` MUST
- `delivery-snapshot-isolation` MUST
- `mapped-value-cached-per-context` MUST
- `unmappable-context-skipped` MUST
- `listener-throw-does-not-halt-delivery` MUST
- `unavailable-context-does-not-halt-delivery` MUST
- `listener-count-reflects-registrations` MUST
- `subscribe-implements-callable-event-contract` MUST
- `subscribe-rejects-non-function-listener` MUST
- `this-args-truthy-gate` MUST
- `registration-identity-monotonic` MUST
- `disposable-removes-exactly-one-registration` MUST
- `disposable-idempotence-delegated` MUST
- `disposable-creation-failure-rolls-back` MUST
- `disposable-pushed-to-array-argument` MUST
- `remove-listeners-by-owner` MUST
- `owner-held-weakly-by-identity-only` MUST
- `timer-window-schedules-once` MUST
- `immediate-window-synchronous-close` MUST
- `window-scheduling-has-no-cancellation` MUST
- `logging-conformance` MUST

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

