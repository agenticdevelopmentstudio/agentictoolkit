<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-window--part-5 · source: extension-host-vs-code-api-main-thread-window.md -->

# MainThreadWindow — continued (part 5)

## Platform Notes

- **SwiftUI**: Not applicable — this is app/extension-host plumbing with no view; a SwiftUI host would call the same presenter protocols this adaptor calls, not reimplement this type.
- **AppKit/UIKit**: This is the source; the surrounding app is macOS-only (see `project.yml`'s `AgenticToolkitMacOS` target), and there is no iOS/UIKit build of this file today.
- **Compose (Android/Kotlin)**: A Kotlin port would model this as a class implementing the JS-engine bridge callbacks (e.g. via a J2V8/QuickJS binding) that dispatches to Kotlin interfaces mirroring the four presenter protocols, with the same argument-shape validation performed before any dispatch, and the same permanently-unsettled-on-dispose behavior for a `Deferred`/`CompletableDeferred` standing in for the pending promise.
- **React/Web**: A web-hosted equivalent would run the extension in a Web Worker or sandboxed iframe and marshal these same calls over `postMessage`, replacing the synchronous JavaScriptCore bridge with an asynchronous message protocol; the argument-shape validation, the last-wins close-affordance rule, and the unclamped-`Infinity`-priority behavior would all need to be reproduced explicitly, since none of them fall out of `postMessage`'s own semantics.
- **WinUI 3**: A .NET port would implement this as a class exposing the same members to a `ClearScript` or `Jint` JavaScript engine instance, using `TaskCompletionSource<object>` in place of `PromiseSettlementBox` (with `TrySetResult`/`TrySetCanceled` guarded the same way `isDisposed` is checked here, since `TaskCompletionSource` has no built-in "leave pending forever" state — a disposed instance would need to hold the `TaskCompletionSource` without ever completing it), `ObservableCollection<T>`/`INotifyPropertyChanged` for a status bar item's live-mutable properties surfaced back to the engine, `DispatcherQueue.TryEnqueue` to guarantee the same single-thread affinity `@MainActor` guarantees here, and a `System.Text.Json`-based decoder for the same options-object shape checks (`valueSelection`, `canPickMany`, etc.) this file performs by hand against `JSValue`.

