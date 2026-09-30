<!-- leaf: implement-extension/webview-view-controller--edge-cases · source: extension-webview-view-controller.md -->

# ExtensionWebviewViewController

**Rules** (cite as `implement-extension/webview-view-controller--edge-cases#<slug>`):

- `null-empty-input` MUST — resolve returning nil — no provider is available at all — the component MUST remain showing the placeholder built in …
- `concurrent-access` MUST — Not a hazard, by construction: the whole class, and the ContributedWebviewResolving closure type it is handed, are …
- `error-states` MUST — Neither an extension's process crashing nor being force-quit produces a state this file distinguishes — the only signal …

## Edge Cases

- **Null/empty input**: `resolve` returning `nil` — no provider is available at all — the component MUST remain showing the placeholder built in `loadView()` indefinitely (see `remains-on-placeholder-when-unresolved`). Likewise, if `resolve` returns a non-nil panel but its completion closure is never called, the component MUST NOT adopt that panel (see `no-adoption-without-completion`, which defines adoption entirely in terms of that closure firing).
- **Boundary values**: Not applicable. This component takes no numerically- or size-bounded input; its constructor arguments are a `ContributedView` value, a display-name string, and a resolver closure, none of which carry a minimum or maximum in this file.
- **Concurrent access**: Not a hazard, by construction: the whole class, and the `ContributedWebviewResolving` closure type it is handed, are declared `@MainActor` (MUST, see `main-actor-confined`), so `panel`, `isResolved`, `content`, `isBeingDiscarded`, and `onTitleChange` are read and written only on the main actor. The source's own note that the completion runs "synchronously if [the extension] is already awake, and a turn or two later if it had to be activated first" describes timing relative to `resolve` returning, not a different execution context.
- **Error states**: Neither an extension's process crashing nor being force-quit produces a state this file distinguishes — the only signal it reacts to is `onRemovalRequested`, which reverts to the same placeholder shown for a view whose provider never ran (MUST, see `panel-removal-reverts-to-placeholder`); there is no separate "something went wrong" explanation. A panel that disposes itself before `onRemovalRequested` is ever assigned — for example, during `resolve`, before it is returned — replays that disposal synchronously the instant `viewDidLoad()` assigns the callback; because `content` is still the initial placeholder at that point, `panel-removal-reverts-to-placeholder`'s own guard makes this a no-op rather than a double-build.
- **Offline or disconnected state**: Not applicable. This file makes no network request of its own; any network activity a resolved panel's page performs happens inside the extension's own content, outside this file.
