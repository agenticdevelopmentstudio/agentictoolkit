<!-- leaf: implement-general-controller/webview-panel-view-controller--test-vectors-part-3 · source: webview-panel-view-controller.md -->

# WebviewPanelViewController — Conformance Test Vectors (part 3)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wpvc-052 | restoration-state-snapshots-current-values | Set `viewType`, `title`, `state` (via `setState`), and `options` to known values, read the restoration snapshot | All four match the current values |
| wpvc-053 | panel-title-defaults-empty-string | With `title` unset, read the `ExtensionWebviewPanel` title accessor | Returns an empty string |
| wpvc-054 | pane-title-defaults-to-view-type | With `title` unset and a known `viewType`, read the `PaneTitleProviding` title accessor | Returns `viewType` |
| wpvc-055 | pane-title-change-callback-aliases-title-callback | Install a closure on the `PaneTitleProviding` callback, then change `title` | That closure fires |
| wpvc-056 | teardown-disposes-panel | Call `paneContentWillBeDiscarded()` | The panel becomes disposed and `onDidDispose` fires, identically to a direct `dispose()` call |
| wpvc-057 | debug-only-occlusion-detection-disabled | In a DEBUG build, with the automation flag enabled, call `loadView()` | The web view's window-occlusion paint suppression is disabled when the running WebKit supports the check, and the attempt is silently skipped otherwise; this path does not exist in a Release build |
| wpvc-058 | load-host-document-noop-after-disposal | Assign a new `html` value before `loadView()` has ever run | No load reaches any web view (none exists yet), and no crash occurs |
| wpvc-059 | host-document-bootstrap-precedes-extension-markup | Set `html` to a known extension markup string and call `loadView()` | The wrapped host document's `acquireVsCodeApi()` bootstrap script appears before that markup in document order |
| wpvc-060 | host-document-nil-state-as-undefined | Construct a panel with no restored state and call `loadView()` | The wrapped host document embeds the initial state as the literal `undefined`, not `null` |
| wpvc-061 | content-security-policy-floor | With `options.enableForms == false`, read the scheme handler's `contentSecurityPolicy` | It contains `object-src 'none'`, `base-uri 'none'`, `frame-ancestors 'none'`, and `form-action 'none'` |
| wpvc-062 | content-security-policy-floor | With `options.enableForms == true`, read the scheme handler's `contentSecurityPolicy` | It contains `object-src 'none'`, `base-uri 'none'`, and `frame-ancestors 'none'`, and omits `form-action 'none'` |
| wpvc-063 | reveal-deferred-request-overwritten | With no reveal listener ever installed, call `reveal(preserveFocus: true)` then `reveal(preserveFocus: false)`, then install a listener | The listener is invoked once, immediately, with `false` |
| wpvc-064 | installing-reveal-listener-replays-deferred-reveal | Call `reveal(preserveFocus: true)` before any listener exists, then `dispose()`, then install a reveal listener | The listener is still invoked once, immediately, with `true`, even though the panel is now disposed |
| wpvc-065 | panel-title-setter-assigns-through | Set the `ExtensionWebviewPanel` title accessor (`panelTitle`) to a new string value | `title` equals that value afterward |
| wpvc-066 | relay-drops-unrecognized-messages | Deliver a script message whose body is a dictionary with an unrecognized `kind` string | The panel's message handler is never called |
