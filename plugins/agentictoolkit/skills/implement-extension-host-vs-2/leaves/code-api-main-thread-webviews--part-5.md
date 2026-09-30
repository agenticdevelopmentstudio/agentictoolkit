<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-webviews--part-5 · source: extension-host-vs-code-api-main-thread-webviews.md -->

# MainThreadWebviews — continued (part 5)

**Rules** (cite as `implement-extension-host-vs-2/code-api-main-thread-webviews--part-5#<slug>`):

- `winui-3` MUST — model MainThreadWebviews as a class whose every member runs on a captured DispatcherQueue (the @MainActor equivalent — …

## Localization

`MainThreadWebviews` raises and logs hardcoded English string literals; none carries a localization key, `String(localized:)` call, or String Catalog entry. Every raised message reaches the extension as a thrown JavaScript error, so an extension author sees the literal English text regardless of locale; every logged message reaches only the host's own log.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `vscode.window.createWebviewPanel is unavailable: this extension's host has been torn down.` | Raised by `createWebviewPanel` after the adaptor is disposed. |
| (none — literal only) | `vscode.window.createWebviewPanel's first argument must be a view type string.` | Raised when the first argument is missing or not a string. |
| (none — literal only) | `vscode.window.createWebviewPanel's second argument must be a title string.` | Raised when the second argument is missing or not a string. |
| (none — literal only) | `vscode.window.createWebviewPanel could not open a panel for view type '<viewType>': this app's windows belong to open projects, and none is open.` | Raised when the presenter has nowhere to put the panel. |
| (none — literal only) | `vscode.window.createWebviewPanel could not build a panel object for view type '<viewType>'.` | Raised when a presented panel could not be given a JavaScript object. |
| (none — literal only) | `vscode.window.registerWebviewPanelSerializer is unavailable: this extension's host has been torn down.` | Raised by `registerWebviewPanelSerializer` after disposal. |
| (none — literal only) | `vscode.window.registerWebviewPanelSerializer's first argument must be a view type string.` | Raised when the first argument is not a string. |
| (none — literal only) | `vscode.window.registerWebviewPanelSerializer's second argument must be an object with a deserializeWebviewPanel(panel, state) method.` | Raised when the second argument lacks a callable `deserializeWebviewPanel`. |
| (none — literal only) | `vscode.window.registerWebviewViewProvider is unavailable: this extension's host has been torn down.` | Raised by `registerWebviewViewProvider` after disposal. |
| (none — literal only) | `vscode.window.registerWebviewViewProvider's first argument must be a view id string.` | Raised when the first argument is not a string. |
| (none — literal only) | `vscode.window.registerWebviewViewProvider's second argument must be an object with a resolveWebviewView(webviewView, context, token) method.` | Raised when the second argument lacks a callable `resolveWebviewView`. |
| (none — literal only) | `vscode.Webview.asWebviewUri needs a Uri.` | Raised when `asWebviewUri`'s argument is missing or unparseable. |
| (none — literal only, log only) | `<extension> asked for a webview panel of type <viewType>, but there is no window to put it in` | Logged at error level alongside the "no window open" raise. |
| (none — literal only, log only) | `A panel of view type <viewType> for <extension> could not be given a JavaScript object; it was closed again` | Logged at error level alongside the "could not build a panel object" raise. |
| (none — literal only, log only) | `The <panel-or-view kind> <identifier> was closed before <extension> could fill it; it is not handed over` | Logged at notice level by `logRefusedHandover`. |
| (none — literal only, log only) | `<extension> registered a second webview panel serializer for view type <viewType>; the later one wins` | Logged at error level on a duplicate serializer registration. |
| (none — literal only, log only) | `<extension> registered a second webview view provider for view id <viewID>; the later one wins` | Logged at error level on a duplicate provider registration. |
| (none — literal only, log only) | `<extension>'s deserializeWebviewPanel threw for view type <viewType>: <reason>` / `could not be invoked for view type <viewType>` | Logged at error level on `restore`'s throw/unavailable outcomes. |
| (none — literal only, log only) | `<extension>'s resolveWebviewView threw for view id <viewID>: <reason>` / `could not be invoked for view id <viewID>` | Logged at error level on `resolveWebviewView`'s throw/unavailable outcomes. |

## Privacy

- **Data collected**: `MainThreadWebviews` collects no data of its own; `panels` holds, for each live panel, the extension-supplied panel handle and (indirectly, through the JavaScript objects built over it) the extension's `JSContext` and every callback it registered. `postMessage` payloads and posted messages pass through untouched — never copied, stored, or inspected beyond the `Any`-to-`JSValue` bridging `VSCodeAPI` performs. `NotImplementedLedger` rows carry only member-path strings and the extension identifier — no message content, no page content, no file paths beyond what an extension itself declared as a resource root.
- **Storage**: `MainThreadWebviews` itself performs no storage; `panels`, `serializers`, and `viewProviders` are in-memory only, for the adaptor's lifetime. A panel's persisted state (`WebviewPanelState`) is a collaborator's responsibility, not this file's — `restore` only reads a `state` string handed to it.
- **Transmission**: nothing here leaves the process; `postMessage`, `onDidReceiveMessage`, and every registration round-trip stay within one process between the host and a `JSContext` it owns. A webview's own page content may load resources over the `agentic-webview://` scheme or the network, but that is the page's own traffic, not this adaptor's.
- **Retention**: a panel's model and every callback it wired are retained in `panels` until `forget` runs — on disposal from either side or on `dispose()` — per **panels-dictionary-is-the-sole-strong-reference** and **dispose-clears-every-registry**.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadWebviews.swift` imports `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWebviews.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration; the concrete `ExtensionWebviewPanel` it addresses is an `NSViewController`-backed WebKit host outside this file's own scope.
- **Compose**: model `MainThreadWebviews` as a Kotlin `class MainThreadWebviews(...)` confined to the main dispatcher, with `panels`/`serializers`/`viewProviders` as plain `MutableMap`s guarded by that confinement (no `Mutex` needed, matching the source's own single-actor argument). The webview surface itself becomes a `WebView` (or an Android `WebView`)-backed handle conforming to a `ExtensionWebviewPanel`-equivalent interface, and the extension callback's `JSValue` becomes whatever function-reference type the host's own JavaScript engine binding exposes.
- **React/Web**: this component's own upstream is VS Code's real `MainThreadWebviews` (`mainThreadWebviewViews.ts`/`mainThreadWebviewPanels.ts`), already TypeScript, so a web port is closer to restoring the original than translating it — including its own `Disposable`-returning registration and native `Promise`-returning `postMessage`, rather than the settled-synchronously `Thenable` this host constructs by hand.
- **WinUI 3**: model `MainThreadWebviews` as a class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue`). The webview surface is a `WebView2`-backed control; `asWebviewUri`'s custom scheme becomes a `WebView2.AddWebResourceRequestedFilter` handler keyed the same way (panel id as authority), and the extension callback becomes whatever the chosen JavaScript engine binding uses (ClearScript's `ScriptObject`/`dynamic`, or Jint's `JsValue`) standing in for `JavaScriptCore.JSValue`.

