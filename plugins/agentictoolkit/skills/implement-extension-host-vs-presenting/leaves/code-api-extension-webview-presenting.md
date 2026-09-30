<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-webview-presenting · source: extension-host-vs-code-api-extension-webview-presenting.md -->

**Rules** (cite as `implement-extension-host-vs-presenting/code-api-extension-webview-presenting#<slug>`):

- `request-value-semantics` MUST
- `request-resolved-roots-passthrough` MUST
- `request-extension-attribution` MUST
- `presenter-main-actor-isolation` MUST
- `presenter-nil-on-no-placement` MUST
- `presenter-single-panel-per-call` MUST
- `presenter-wired-before-revealed` MUST
- `presenter-reveals-once` MUST
- `presenter-failed-placement-reveals-nothing` MUST
- `panel-main-actor-isolation` MUST
- `panel-identity` MUST
- `panel-title-mutation` MUST
- `panel-html-mutation` MUST
- `panel-resource-roots-mutation` MUST
- `panel-options-mutation` MUST
- `panel-state-readback` MUST
- `panel-message-callback` MUST
- `panel-dispose-callback` MUST
- `panel-disposed-flag` MUST
- `panel-post-message-result` MUST
- `panel-reveal-preserve-focus` MUST
- `panel-dispose-idempotent` MUST
- `panel-not-sendable-by-design` MUST

# ExtensionWebviewPresenting

## Overview

`ExtensionWebviewPresenting`, declared in `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionWebviewPresenting.swift`, is the extension host's seam for `vscode.window.createWebviewPanel`: a one-method, `@MainActor` protocol that turns a fully-resolved `ExtensionWebviewPanelRequest` into a live `ExtensionWebviewPanel` handle, or into `nil` when there is nowhere to put one. The same file declares the request value type the protocol's method consumes and the panel handle protocol its method returns — three types that together are the whole contract between `MainThreadWebviews` (the adaptor that resolves a JavaScript `createWebviewPanel` call into a request and translates a `nil` result into a raised JS exception) and whatever actually builds and places a pane. `PaneWebviewPresenter`, in the sibling file `Webview/PaneWebviewPresenter.swift`, is the one production conformer: it builds a `WebviewPanelViewController` from the request, asks an app-supplied `place` closure where to put it, wires the placement's `reveal`/`remove` closures onto the panel, and reveals the panel — honoring `preserveFocus` — before returning it. Per `PaneWebviewPresenter`'s own doc comment, this protocol is a fifth presenter beside the four `MainThreadWindow` already takes (message, quick pick, input box, and status bar item), and it alone needs a window manager and a pane tree to do its job, which is why the placement decision is a closure the app supplies rather than something this protocol or its production conformer performs itself.

`ExtensionWebviewPanel` is the handle a caller receives back: a `@MainActor`, `AnyObject`-constrained protocol exposing a stable `panelID`, a settable `panelTitle` and `html`, settable `localResourceRoots` and `options`, a read-only `state` string mirroring the webview script's own persisted state, an `onDidReceiveMessage` callback for messages the webview's script posts, an `onDidDispose` callback fired exactly once on disposal, a read-only `isDisposed` flag, a `post(message:)` method that reports whether delivery succeeded, a `reveal(preserveFocus:)` method, and a `dispose()` method. `ExtensionWebviewPanelRequest` is the plain `Sendable`, `Equatable` value type `MainThreadWebviews` builds after validating and resolving a JavaScript `createWebviewPanel` call's arguments: `viewType`, `title`, `options` (a `WebviewPanelOptions`, see the related recipe), the already-resolved `localResourceRoots`, `preserveFocus`, and `extensionIdentifier`.

## Behavioral Requirements

- **request-value-semantics**: `ExtensionWebviewPanelRequest` MUST be a `Sendable`, `Equatable` value type (a `struct`) with a memberwise `init`, carrying `viewType: String`, `title: String`, `options: WebviewPanelOptions`, `localResourceRoots: [URL]`, `preserveFocus: Bool`, and `extensionIdentifier: String` verbatim from the caller that built it.
- **request-resolved-roots-passthrough**: `localResourceRoots` on the request MUST be the already-resolved, absolute set of directories the webview may load local resources from; `ExtensionWebviewPresenting`'s conformer MUST pass this value through unmodified rather than re-deriving it from `options.declaredLocalResourceRoots`.
- **request-extension-attribution**: `extensionIdentifier` MUST identify which extension asked for the panel, so a caller can attribute the panel without re-deriving that fact from elsewhere.
- **presenter-main-actor-isolation**: `ExtensionWebviewPresenting` MUST be declared `@MainActor`; `presentWebviewPanel(_:)` and every read of state it depends on MUST execute on the main actor.
- **presenter-nil-on-no-placement**: `presentWebviewPanel(_:)` MUST return `nil` when there is nowhere to place the panel (for example, no project window is open), rather than throwing or returning a partially-placed panel.
- **presenter-single-panel-per-call**: `presentWebviewPanel(_:)` MUST create and return exactly one new panel per call; it MUST NOT return a panel created by a previous call.
- **presenter-wired-before-revealed**: when placement succeeds, the returned panel's placement callbacks (the pane's `reveal`/`remove` verbs) MUST be installed on the panel before the panel is revealed, so a caller-initiated reveal during that same call always has a working placement behind it.
- **presenter-reveals-once**: a successful `presentWebviewPanel(_:)` call MUST reveal the returned panel exactly once, honoring the request's `preserveFocus`, as part of the same call — never as a separate step the caller must remember to invoke.
- **presenter-failed-placement-reveals-nothing**: when placement fails and `presentWebviewPanel(_:)` returns `nil`, `reveal` MUST NOT be called on any panel.
- **panel-main-actor-isolation**: `ExtensionWebviewPanel` MUST be declared `@MainActor` and constrained to `AnyObject`; every member MUST be usable only on the main actor, matching AppKit's own main-thread requirement for window and view mutation.
- **panel-identity**: `panelID` MUST be a stable, get-only identifier for the panel's entire lifetime.
- **panel-title-mutation**: `panelTitle` MUST be settable, and assigning it MUST change the panel's displayed title.
- **panel-html-mutation**: `html` MUST be settable, and assigning it MUST replace the panel's rendered content.
- **panel-resource-roots-mutation**: `localResourceRoots` MUST be settable, so a webview *view* provider (which receives an already-built panel) can change which local directories the panel's scheme handler may read from after creation.
- **panel-options-mutation**: `options` MUST be settable, so `enableScripts`, `enableForms`, and `declaredLocalResourceRoots` can change after creation.
- **panel-state-readback**: `state` MUST expose the most recent state the webview's own script serialized via `vscode.setState`/`getState`, or `nil` when no state has ever been set.
- **panel-message-callback**: `onDidReceiveMessage` MUST be invoked for every message the webview's script posts via `acquireVsCodeApi().postMessage`.
- **panel-dispose-callback**: `onDidDispose` MUST be invoked exactly once when the panel is disposed, whether disposal was requested by the extension (`dispose()`) or driven by the user closing the pane.
- **panel-disposed-flag**: `isDisposed` MUST become `true` once the panel is disposed and MUST remain `true` afterward, so a caller can test disposal before acting on a handle that may have gone stale — the guard `MainThreadWebviews`'s `restore` and `resolveWebviewView` both perform before adopting a hand-over.
- **panel-post-message-result**: `post(message:)` MUST return `false` when the panel is disposed or the message otherwise cannot be delivered, and MUST return `true` when the message was handed to the webview successfully.
- **panel-reveal-preserve-focus**: `reveal(preserveFocus:)` MUST bring the panel's pane forward and MUST leave keyboard focus wherever it already was when `preserveFocus` is `true`.
- **panel-dispose-idempotent**: `dispose()` MUST be safe to call more than once; a second call MUST NOT remove the pane a second time or fire `onDidDispose` again.
- **panel-not-sendable-by-design**: `ExtensionWebviewPanel` MUST NOT conform to `Sendable`; because it is `@MainActor`-isolated and constrained to `AnyObject`, the compiler already prevents any instance from crossing an actor boundary, making a `Sendable` conformance unnecessary.

## Configuration

| Parameter | Type | Source | Effect |
|-----------|------|--------|--------|
| `viewType` | `String` | Caller (`MainThreadWebviews`, resolved from the JavaScript `createWebviewPanel` call) | Identifies the contributed view type the panel is built for; passed through unvalidated by this seam. |
| `title` | `String` | Caller | The panel's initial displayed title. |
| `options` | `WebviewPanelOptions` | Caller | Carries `enableScripts`, `enableForms`, and `declaredLocalResourceRoots`; see the related `WebviewPanelOptions` recipe. |
| `localResourceRoots` | `[URL]` | Caller, already resolved | The absolute set of directories the built panel's webview may load local resources from. |
| `preserveFocus` | `Bool` | Caller | Honored by `reveal(preserveFocus:)` as part of the same `presentWebviewPanel(_:)` call that creates the panel. |
| `extensionIdentifier` | `String` | Caller | Identifies the requesting extension; carried on the request for attribution by callers, but not read or acted on by this file itself. |
| `place` | `(WebviewPanelViewController) -> ExtensionWebviewPlacement?` | App, supplied to `PaneWebviewPresenter.init(place:)` | Decides where (or whether) the built panel goes in the pane tree; this closure lives in `PaneWebviewPresenter`, the production conformer, not in the protocols this recipe describes. |

## Privacy

- **Data collected**: the given source collects no data of its own; `localResourceRoots` (file-system paths) and `extensionIdentifier` are carried through as opaque values, not inspected, logged, or transformed by this file.
- **Storage**: the given source performs no storage of its own; a panel's `state` string is held only in memory by whatever conforms to `ExtensionWebviewPanel` and is not persisted by this protocol.
- **Transmission**: the given source performs no network transmission of its own.
- **Retention**: the given source retains nothing beyond the lifetime of the panel handle itself.

