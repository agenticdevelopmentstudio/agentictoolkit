<!-- leaf: implement-extension-host-vs-1/code-api-extension-event--part-2 · source: extension-host-vs-code-api-extension-event.md -->

# ExtensionEvent — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-1/code-api-extension-event--part-2#<slug>`):

- `winui-3` MUST — model ExtensionEventEmitter<TPayload> as a generic class whose every member runs on a captured DispatcherQueue (the …

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

## Localization

`subscribe`'s two refusal messages are hardcoded English string literals with no localization key, `String(localized:)` call, or String Catalog entry: `"\(path) requires a listener function."` and `"\(path) could not create a Disposable in context '\(VSCodeAPI.name(of: context))'."`. Both reach the extension as a thrown JavaScript error via `VSCodeAPI.raise`, so an extension author sees the literal English text regardless of locale. The three `Self.logger.error(...)` messages in `deliver(_:)` are likewise hardcoded English, but those reach only the host's own log, never the extension.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `<path> requires a listener function.` | Raised when `subscribe`'s first argument fails the `Function` instance check. |
| (none — literal only) | `<path> could not create a Disposable in context '<context name>'.` | Raised when `VSCodeAPI.disposable(in:onDispose:)` returns `nil`. |

## Privacy

- **Data collected**: `ExtensionEventEmitter` collects no data of its own; it relays whatever `Payload` value a host-side caller fires (for `onDidChangeDiagnostics`, a list of changed `URL`s) to whichever `JSValue` listeners an extension has subscribed. It also holds each listener's `JSValue` and optional `thisArgs` `JSValue` strongly for the registration's lifetime, per its own doc comment on lifetime.
- **Storage**: `ExtensionEventEmitter` performs no storage of its own; `registrations` and `queue` are in-memory only and exist for the emitter's lifetime.
- **Transmission**: nothing here leaves the process; delivery is an in-process JavaScriptCore call from Swift into a `JSContext` the same process owns.
- **Retention**: a subscribed listener's `JSValue` (and the `JSContext` it keeps alive) is retained until its `Disposable` is disposed or `removeListeners(ownedBy:)` removes it; the doc comment on `ExtensionEventEmitter` states this explicitly as "not a cycle" but a real extension-outlives-host lifetime hazard that `removeListeners(ownedBy:)` exists to bound.

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
