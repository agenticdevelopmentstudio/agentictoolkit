<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-webviews--logging · source: extension-host-vs-code-api-main-thread-webviews.md -->

# MainThreadWebviews

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadWebviews` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|
| `createWebviewPanel` presented against no open window | error | `<extension> asked for a webview panel of type <viewType>, but there is no window to put it in` |
| A presented panel could not be given a JavaScript object | error | `A panel of view type <viewType> for <extension> could not be given a JavaScript object; it was closed again` |
| A restored panel or contributed view could not be given a JavaScript object | error | `A restored panel of view type <viewType> could not be given a JavaScript object; it stays blank` / `The contributed view <viewID> could not be given a JavaScript object; it stays empty` |
| A hand-over panel was already closed | notice | `The <kind> <identifier> was closed before <extension> could fill it; it is not handed over` |
| A second serializer or provider registered under the same key | error | `<extension> registered a second webview panel serializer for view type <viewType>; the later one wins` / the provider equivalent |
| A registered serializer or provider has no callable method to invoke | error | `<extension> has a serializer for view type <viewType> but no deserializeWebviewPanel to call` / the provider equivalent |
| `deserializeWebviewPanel` or `resolveWebviewView` threw | error | `<extension>'s deserializeWebviewPanel threw for view type <viewType>: <reason>` / the `resolveWebviewView` equivalent |
| `deserializeWebviewPanel` or `resolveWebviewView` could not be dispatched | error | `<extension>'s deserializeWebviewPanel could not be invoked for view type <viewType>` / the `resolveWebviewView` equivalent |

No other event in this file is logged: every `createWebviewPanel`, `registerWebviewPanelSerializer`, and `registerWebviewViewProvider` argument-validation refusal is surfaced directly to the extension as a raised exception instead of being logged, per the corresponding Behavioral Requirements above.
